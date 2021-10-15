defmodule Exq.Redis.JobStat do
  @moduledoc """
  The JobStat module encapsulates storing system-wide stats on top of Redis
  It aims to be compatible with the Sidekiq stats format.
  """

  require Logger
  alias Exq.Support.{Binary, Process, Job, Time, Node}
  alias Exq.Redis.{Connection, JobQueue}

  def record_processed_commands(namespace, _job, current_date \\ DateTime.utc_now()) do
    {time, date} = Time.format_current_date(current_date)

    [
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ]
  end

  def record_processed(redis, namespace, job, current_date \\ DateTime.utc_now()) do
    instr = record_processed_commands(namespace, job, current_date)
    {:ok, [count, _, _, _]} = Connection.qp(redis, instr)
    {:ok, count}
  end

  def record_failure_commands(namespace, _error, _job, current_date \\ DateTime.utc_now()) do
    {time, date} = Time.format_current_date(current_date)

    [
      ["INCR", JobQueue.full_key(namespace, "stat:failed")],
      ["INCR", JobQueue.full_key(namespace, "stat:failed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:failed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:failed:#{date}")]
    ]
  end

  def record_failure(redis, namespace, error, job, current_date \\ DateTime.utc_now()) do
    instr = record_failure_commands(namespace, error, job, current_date)
    {:ok, [count, _, _, _]} = Connection.qp(redis, instr)
    {:ok, count}
  end

  def add_process_commands(namespace, process_info, serialized_process \\ nil) do
    serialized = serialized_process || Exq.Support.Process.encode(process_info)
    [["HSET", workers_key(namespace, process_info.host), process_info.pid, serialized]]
  end

  def add_process(redis, namespace, process_info, serialized_process \\ nil) do
    instr = add_process_commands(namespace, process_info, serialized_process)
    Connection.qp!(redis, instr)
    :ok
  end

  def remove_process_commands(namespace, process_info) do
    [["HDEL", workers_key(namespace, process_info.host), process_info.pid]]
  end

  def remove_process(redis, namespace, process_info) do
    instr = remove_process_commands(namespace, process_info)
    Connection.qp!(redis, instr)
    :ok
  end

  def cleanup_processes(redis, namespace, host) do
    Connection.del!(redis, workers_key(namespace, host))
    :ok
  end

  def node_ping(redis, namespace, node) do
    key = node_info_key(namespace, node.identity)

    case Connection.qp(
           redis,
           [
             ["MULTI"],
             ["SADD", nodes_key(namespace), node.identity],
             [
               "HMSET",
               key,
               "info",
               Node.encode(node),
               "busy",
               node.busy,
               "beat",
               Time.unix_seconds(),
               "quiet",
               node.quiet
             ],
             ["EXPIRE", key, 60],
             ["RPOP", "#{key}-signals"],
             ["EXEC"]
           ]
         ) do
      {:ok, ["OK", "QUEUED", "QUEUED", "QUEUED", "QUEUED", [_, "OK", 1, signal]]} ->
        signal

      error ->
        Logger.error("Failed to send node stats. Unexpected error from redis: #{inspect(error)}")

        nil
    end
  end

  def node_ids(redis, namespace) do
    Connection.smembers!(redis, nodes_key(namespace))
  end

  def nodes(redis, namespace) do
    commands =
      node_ids(redis, namespace)
      |> Enum.map(fn node_id -> ["HGET", node_info_key(namespace, node_id), "info"] end)

    if Enum.empty?(commands) do
      []
    else
      Connection.qp!(redis, commands)
      |> Enum.flat_map(fn result ->
        if result && result != "" do
          [Node.decode(result)]
        else
          []
        end
      end)
    end
  end

  def prune_dead_nodes(redis, namespace) do
    node_ids = node_ids(redis, namespace)

    commands =
      node_ids
      |> Enum.map(fn node_id -> ["HEXISTS", node_info_key(namespace, node_id), "info"] end)

    if Enum.empty?(commands) do
      []
    else
      dead_node_ids =
        Connection.qp!(redis, commands)
        |> Enum.zip(node_ids)
        |> Enum.flat_map(fn {exists, node_id} ->
          if exists == 0 do
            [node_id]
          else
            []
          end
        end)

      if !Enum.empty?(dead_node_ids) do
        commands = [
          ["SREM", nodes_key(namespace)] ++ dead_node_ids,
          ["DEL"] ++ Enum.map(node_ids, &workers_key(namespace, &1))
        ]

        Connection.qp(redis, commands)
      end
    end
  end

  def busy(redis, namespace) do
    commands =
      node_ids(redis, namespace)
      |> Enum.map(fn node_id -> ["HGET", node_info_key(namespace, node_id), "busy"] end)

    if Enum.empty?(commands) do
      0
    else
      Connection.qp!(redis, commands)
      |> Enum.reduce(0, fn count, sum -> sum + decode_integer(count) end)
    end
  end

  def processes(redis, namespace) do
    commands =
      node_ids(redis, namespace)
      |> Enum.map(fn node_id -> ["HVALS", workers_key(namespace, node_id)] end)

    if Enum.empty?(commands) do
      []
    else
      Connection.qp!(redis, commands)
      |> List.flatten()
      |> Enum.map(&Process.decode/1)
    end
  end

  def find_failed(redis, namespace, jid) do
    redis
    |> Connection.zrange!(JobQueue.full_key(namespace, "dead"), 0, -1)
    |> JobQueue.search_jobs(jid)
  end

  def find_failed(redis, namespace, score, jid, options) do
    find_by_score_and_jid(redis, JobQueue.full_key(namespace, "dead"), score, jid, options)
  end

  def find_retry(redis, namespace, score, jid, options) do
    find_by_score_and_jid(redis, JobQueue.full_key(namespace, "retry"), score, jid, options)
  end

  def find_scheduled(redis, namespace, score, jid, options) do
    find_by_score_and_jid(redis, JobQueue.full_key(namespace, "schedule"), score, jid, options)
  end

  def remove_queue(redis, namespace, queue) do
    Connection.qp(redis, [
      ["SREM", JobQueue.full_key(namespace, "queues"), queue],
      ["DEL", JobQueue.queue_key(namespace, queue)]
    ])
  end

  def remove_failed(redis, namespace, jid) do
    {:ok, failure} = find_failed(redis, namespace, jid)

    Connection.qp(redis, [
      ["DECR", JobQueue.full_key(namespace, "stat:failed")],
      ["ZREM", JobQueue.full_key(namespace, "dead"), Job.encode(failure)]
    ])
  end

  def clear_failed(redis, namespace) do
    Connection.qp(redis, [
      ["SET", JobQueue.full_key(namespace, "stat:failed"), 0],
      ["DEL", JobQueue.full_key(namespace, "dead")]
    ])
  end

  def clear_processes(redis, namespace) do
    commands =
      node_ids(redis, namespace)
      |> Enum.map(fn node_id -> ["DEL", workers_key(namespace, node_id)] end)

    if Enum.empty?(commands) do
      0
    else
      Connection.qp!(redis, commands)
    end
  end

  def realtime_stats(redis, namespace) do
    failure_keys = realtime_stats_scanner(redis, JobQueue.full_key(namespace, "stat:failed_rt:*"))

    success_keys =
      realtime_stats_scanner(redis, JobQueue.full_key(namespace, "stat:processed_rt:*"))

    formatter = realtime_stats_formatter(redis, namespace)
    failures = formatter.(failure_keys, "stat:failed_rt:")
    successes = formatter.(success_keys, "stat:processed_rt:")

    {:ok, failures, successes}
  end

  defp realtime_stats_scanner(redis, namespace) do
    {:ok, [[cursor, result]]} =
      Connection.qp(redis, [["SCAN", 0, "MATCH", namespace, "COUNT", 1_000]])

    realtime_stats_scan_keys(redis, namespace, cursor, result)
  end

  defp realtime_stats_scan_keys(_redis, _namespace, "0", accumulator) do
    accumulator
  end

  defp realtime_stats_scan_keys(redis, namespace, cursor, accumulator) do
    {:ok, [[new_cursor, result]]} =
      Connection.qp(redis, [["SCAN", cursor, "MATCH", namespace, "COUNT", 1_000]])

    realtime_stats_scan_keys(redis, namespace, new_cursor, accumulator ++ result)
  end

  defp realtime_stats_formatter(redis, namespace) do
    fn keys, ns ->
      if Enum.empty?(keys) do
        []
      else
        {:ok, counts} = Connection.qp(redis, Enum.map(keys, &["GET", &1]))

        Enum.map(keys, &Binary.take_prefix(&1, JobQueue.full_key(namespace, ns)))
        |> Enum.zip(counts)
      end
    end
  end

  def get_count(redis, namespace, key) do
    Connection.get!(redis, JobQueue.full_key(namespace, "stat:#{key}"))
    |> decode_integer()
  end

  def get_counts(redis, namespace, keys) do
    {:ok, results} =
      Connection.q(redis, ["MGET" | Enum.map(keys, &JobQueue.full_key(namespace, "stat:#{&1}"))])

    Enum.map(results, &decode_integer/1)
  end

  def decode_integer(:undefined), do: 0
  def decode_integer(nil), do: 0
  def decode_integer(count) when is_integer(count), do: count

  def decode_integer(count) when is_binary(count) do
    {count, _} = Integer.parse(count)
    count
  end

  defp find_by_score_and_jid(redis, zset, score, jid, options) do
    redis
    |> Connection.zrangebyscore!(zset, score, score)
    |> JobQueue.search_jobs(jid, !Keyword.get(options, :raw, false))
  end

  defp workers_key(namespace, node_id) do
    JobQueue.full_key(namespace, "#{node_id}:workers")
  end

  defp nodes_key(namespace) do
    "#{namespace}:processes"
  end

  defp node_info_key(namespace, node_id) do
    "#{namespace}:#{node_id}"
  end
end
