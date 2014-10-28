defmodule Exq.Stats do
  use Timex

  def record_processed(redis, namespace, job) do
    count = Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed"))
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed:#{date}"))
    {:ok, count}
  end

  def record_failure(redis, namespace, error, job) do
    count = Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed"))
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed:#{date}"))

    failed_at = DateFormat.format!(Date.local, "{ISO}")

    job = Poison.decode!(job, as: Exq.Job)
    job = %{job | failed_at: failed_at, error_class: "ExqGenericError", error_message: error}
    job_json = Poison.encode!(job, %{})

    Exq.Redis.rpush!(redis, Exq.RedisQueue.full_key(namespace, "failed"), job_json)

    {:ok, count}
  end

  def find_failed(redis, namespace, jid) do
    errors = Exq.Redis.lrange!(redis, Exq.RedisQueue.full_key(namespace, "failed"))

    finder = fn({j, idx}) -> 
      job = Poison.decode!(j, as: Exq.Job)
      job.jid == jid
    end

    error = Enum.find(Enum.with_index(errors), finder)
   
    case error do
      nil ->
        {:not_found, nil}
      _ ->
        {job, idx} = error
        {:ok, job, idx}
    end
  end
end
  