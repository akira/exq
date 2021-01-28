defmodule Exq.Redis.JobStat do
  @moduledoc """
  The JobStat module encapsulates storing system-wide stats on top of Redis
  It aims to be compatible with the Sidekiq stats format.
  """

  require Logger
  alias Exq.Support.{Binary, Process, Job, Time}
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

  def add_process_commands(namespace, process_info, _) do
    name = supervisor_worker_name(namespace, process_info)
    string_pid = :erlang.pid_to_list(process_info.pid)
    [
      ["SADD", JobQueue.full_key(namespace, "processes"), name], # ensure supervisor worker is added to list
      ["HINCRBY", name, "busy", "1"],
      ["HSET", "#{name}:workers", string_pid, Poison.encode!(%{
        run_at: process_info.started_at,
        pid: string_pid,
        payload: serialize_processing_payload(process_info.job),
        hostname: process_info.hostname,
        queue: process_info.job && process_info.job.queue
      })]
    ]
  end

  def add_process(redis, namespace, process_info, serialized_process \\ nil) do
    instr = add_process_commands(namespace, process_info, serialized_process)
    Connection.qp!(redis, instr)
    :ok
  end

  def remove_process_commands(namespace, process_info, serialized_process \\ nil) do
    name = supervisor_worker_name(namespace, process_info)
    [
      ["HINCRBY", name, "busy", "-1"],
      ["HDEL", "#{name}:workers", :erlang.pid_to_list(process_info.pid)],
    ]
  end

  def remove_process(redis, namespace, process_info, serialized_process \\ nil) do
    instr = remove_process_commands(namespace, process_info, serialized_process)
    Connection.qp!(redis, instr)
    :ok
  end

  def cleanup_processes(redis, namespace, hostname, master_pid) do
    processes = JobQueue.full_key(namespace, "processes")
    master_pid_string = "#{:erlang.pid_to_list(master_pid)}"
    instr = Connection.smembers!(redis, processes)
    |> Enum.filter(fn(key) -> key =~ "#{hostname}:" end)
    |> Enum.filter(fn(key) -> ((Connection.hget!(redis, key, "info") || '{}') |> Poison.decode!)["pid"]  != master_pid_string end)
    |> Enum.flat_map(fn(key) -> [["SREM", processes, key], ["DEL", "#{processes}:workers"]] end)


    if Enum.count(instr) > 0 do
      Connection.qp!(redis, instr)
    end
    :ok
  end

  def busy(redis, namespace) do
    (Connection.smembers!(redis, JobQueue.full_key(namespace, "processes")) || [])
    |> Enum.map(fn(key) -> Connection.hlen!(redis, "#{key}:workers") end)
    |> Enum.sum
  end

  def processes(redis, namespace) do
    (Connection.smembers!(redis, JobQueue.full_key(namespace, "processes")) || [])
    |> Enum.flat_map(fn(key) -> Connection.hvals!(redis, "#{key}:workers") end)
    |> Enum.map(&Process.decode(&1))
  end

  def find_failed(redis, namespace, jid) do
    redis
    |> Connection.zrange!(JobQueue.full_key(namespace, "dead"), 0, -1)
    |> JobQueue.search_jobs(jid)
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
    Connection.del!(redis, JobQueue.full_key(namespace, "processes"))
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
    case Connection.get!(redis, JobQueue.full_key(namespace, "stat:#{key}")) do
      :undefined ->
        0

      nil ->
        0

      count when is_integer(count) ->
        count

      count ->
        {val, _} = Integer.parse(count)
        val
    end
  end

  defp supervisor_worker_name(namespace, process_info) do
    JobQueue.full_key(namespace, "#{process_info.hostname}:elixir")
  end

  defp serialize_processing_payload(nil) do
    %{}
  end

  defp serialize_processing_payload(job) do
    %{
      queue: job.queue,
      class: job.class,
      args: job.args,
      jid: job.jid,
      created_at: job.enqueued_at,
      enqueued_at: job.enqueued_at
    }
  end

  def status_process_commands(namespace, node_id, started_at, master_pid, queues, work_table, poll_timeout) do
    name = redis_worker_name(namespace, node_id)
    [
      ["SADD", JobQueue.full_key(namespace, "processes"), name],
      ["HSET", name, "quiet", "false"],
      ["HSET", name, "info", Poison.encode!(%{ hostname: node_id, started_at: started_at, pid: "#{:erlang.pid_to_list(master_pid)}", concurrency: concurrency_count(queues, work_table), queues: queues})],
      ["HSET", name, "beat", Time.unix_seconds],
      ["EXPIRE", name, (round(poll_timeout / 1000) + 5)]
    ]
  end

  defp redis_worker_name(namespace, node_id) do
    JobQueue.full_key(namespace, "#{node_id}:elixir")
  end

  defp concurrency_count(queues, work_table) do
    Enum.map(queues, fn(q) ->
      [{_, concurrency, _}] = :ets.lookup(work_table, q)
      cond do
        concurrency == :infinite -> 1000000
        true -> concurrency
      end
    end)
    |> Enum.sum
  end
end
