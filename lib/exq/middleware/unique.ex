defmodule Exq.Middleware.Unique do
  @behaviour Exq.Middleware.Behaviour
  alias Exq.Redis.JobQueue
  alias Exq.Middleware.Pipeline

  def before_work(
        %Pipeline{assigns: %{job_serialized: job_serialized, redis: redis, namespace: namespace}} =
          pipeline
      ) do
    job = Exq.Support.Job.decode(job_serialized)

    case job do
      %{unique_until: "start", unique_token: unique_token, retry_count: retry_count, jid: jid}
      when retry_count in [0, nil] ->
        {:ok, _} = JobQueue.unlock(redis, namespace, unique_token, jid)

      _ ->
        :ok
    end

    pipeline
  end

  def after_processed_work(
        %Pipeline{assigns: %{job_serialized: job_serialized, redis: redis, namespace: namespace}} =
          pipeline
      ) do
    job = Exq.Support.Job.decode(job_serialized)

    case job do
      %{unique_until: "success", unique_token: unique_token, jid: jid} ->
        {:ok, _} = JobQueue.unlock(redis, namespace, unique_token, jid)

      _ ->
        :ok
    end

    pipeline
  end

  def after_failed_work(
        %Pipeline{assigns: %{job_serialized: job_serialized, redis: redis, namespace: namespace}} =
          pipeline
      ) do
    job = Exq.Support.Job.decode(job_serialized)

    case job do
      %{unique_until: "success", unique_token: unique_token, jid: jid} ->
        if JobQueue.dead?(job) do
          {:ok, _} = JobQueue.unlock(redis, namespace, unique_token, jid)
        end

      _ ->
        :ok
    end

    pipeline
  end
end
