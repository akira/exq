defmodule Exq.Redis.JobStat do
  require Logger
  use Timex

  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Support.Json
  alias Exq.Support.Job

  def record_processed(redis, namespace, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    [{:ok, count}, {:ok, _,}, {:ok, _}, {:ok, _}] = :eredis.qp(redis,[
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ])
    {:ok, count}
  end

  def record_failure(redis, namespace, error, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    [{:ok, count}, {:ok, _,}, {:ok, _}, {:ok, _}] = :eredis.qp(redis, [
      ["INCR", JobQueue.full_key(namespace, "stat:failed")],
      ["INCR", JobQueue.full_key(namespace, "stat:failed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:failed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:failed:#{date}")]
    ])
    {:ok, count}
  end

end