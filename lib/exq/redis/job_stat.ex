defmodule Exq.Redis.JobStat do
  @moduledoc """
  The JobStat module encapsulates storing system-wide stats on top of Redis
  It aims to be compatible with the Sidekiq stats format.
  """

  require Logger
  alias Exq.Support.Binary
  alias Exq.Support.Process
  alias Exq.Support.Job
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue

  def record_processed(redis, namespace, _job, current_date \\ DateTime.utc_now) do
    {time, date} = format_current_date(current_date)

    {:ok, [count, _, _, _]} = Connection.qp(redis,[
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ])
    {:ok, count}
  end

  def record_failure(redis, namespace, _error, _job, current_date \\ DateTime.utc_now) do
    {time, date} = format_current_date(current_date)

    {:ok, [count, _, _, _]} = Connection.qp(redis, [
      ["INCR", JobQueue.full_key(namespace, "stat:failed")],
      ["INCR", JobQueue.full_key(namespace, "stat:failed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:failed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:failed:#{date}")]
    ])
    {:ok, count}
  end

  def busy(redis, namespace) do
    Connection.scard!(redis, JobQueue.full_key(namespace, "processes"))
  end

  def processes(redis, namespace) do
    list = Connection.smembers!(redis, JobQueue.full_key(namespace, "processes")) || []
    Enum.map(list, &Process.from_json/1)
  end

  def add_process(redis, namespace, process_info) do
    json = Exq.Support.Process.to_json(process_info)
    Connection.sadd!(redis, JobQueue.full_key(namespace, "processes"), json)
    :ok
  end

  def remove_process(redis, namespace, process_info) do
    json = Exq.Support.Process.to_json(process_info)
    Connection.srem!(redis, JobQueue.full_key(namespace, "processes"), json)
    :ok
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
      ["ZREM", JobQueue.full_key(namespace, "dead"), Job.to_json(failure)]
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
    {:ok, [failure_keys, success_keys]} = Connection.qp(redis, [
      ["KEYS", JobQueue.full_key(namespace, "stat:failed_rt:*")],
      ["KEYS", JobQueue.full_key(namespace, "stat:processed_rt:*")]
    ])

    formatter = realtime_stats_formatter(redis, namespace)
    failures = formatter.(failure_keys, "stat:failed_rt:")
    successes = formatter.(success_keys, "stat:processed_rt:")

    {:ok, failures, successes}
  end

  defp realtime_stats_formatter(redis, namespace) do
    fn(keys, ns) ->
      if Enum.empty?(keys) do
        []
      else
        {:ok, counts} = Connection.qp(redis, Enum.map(keys, &(["GET", &1])))
        Enum.map(keys, &(Binary.take_prefix(&1, JobQueue.full_key(namespace, ns))))
        |> Enum.zip(counts)
      end
    end
  end

  defp format_current_date(current_date) do
    date_time =
      current_date
      |> DateTime.to_string

    date =
      current_date
      |> DateTime.to_date
      |> Date.to_string

    {date_time, date}
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
end
