defmodule Exq.Stats do
  use Timex

  def record_processed(redis, namespace, job) do
    pjob = Poison.decode!(job, as: Exq.Job)
    count = Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed"))
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed:#{date}"))
    {:ok, count}
  end

  def record_failure(redis, namespace, error, job) do

    fid = UUID.uuid4
    failed_at = DateFormat.format!(Date.local, "{ISO}")

    job = Poison.decode!(job, as: Exq.Job)
    failed_job = %Exq.FailedJob{args: job.args, class: job.class, error_message: error, failed_at: failed_at, jid: job.jid, queue: job.queue, fid: fid}

    fjob = Poison.encode!(failed_job, %{})
    Exq.Redis.rpush!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed"), fjob)
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.rpush!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed:#{date}"), fjob)
    {:ok, job.jid}
  end

  def find_error(redis, namespace, jid) do
    errors = Exq.Redis.lrange!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed"))

    finder = fn({j, idx}) -> 
      job = Poison.decode!(j, as: Exq.FailedJob)
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
  