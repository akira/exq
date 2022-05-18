defmodule Exq.Middleware.Timeout do
  @behaviour Exq.Middleware.Behaviour
  alias Exq.Redis.JobQueue
  alias Exq.Middleware.Pipeline
  import Pipeline
  require Logger

  def before_work(%{assigns: assigns} = pipeline) do
    job = Exq.Support.Job.decode(assigns.job_serialized)

    expires_time =
      if job.queuing_timeout == :infinity do
        :infinity
      else
        job.enqueued_at + job.queuing_timeout
      end

    now = Exq.Support.Time.unix_seconds()

    # if not expired
    if expires_time == :infinity or now < expires_time do
      pipeline
    else
      Logger.warn(
        "#{job.class}[#{job.jid}] Queuing timeout after #{(now - job.enqueued_at) * 1000} ms"
      )

      JobQueue.remove_job_from_backup(
        assigns.redis,
        assigns.namespace,
        assigns.host,
        assigns.queue,
        assigns.job_serialized
      )

      Exq.Manager.Server.job_terminated(
        assigns.manager,
        assigns.queue,
        false
      )

      pipeline
      |> assign(:job, job)
      |> assign(:worker_module, Exq.Support.Coercion.to_module(job.class))
      |> terminate()
    end
  end

  def after_processed_work(pipeline) do
    pipeline
  end

  def after_failed_work(pipeline) do
    pipeline
  end
end
