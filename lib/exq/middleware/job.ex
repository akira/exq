defmodule Exq.Middleware.Job do
  @behaviour Exq.Middleware.Behaviour
  alias Exq.Redis.JobQueue
  alias Exq.Middleware.Pipeline
  import Pipeline

  def before_work(pipeline) do
    job = Exq.Support.Job.from_json(pipeline.assigns.job_json)
    target = String.replace(job.class, "::", ".")
    [mod | _func_or_empty] = Regex.split(~r/\//, target)

    pipeline
    |> assign(:job, job)
    |> assign(:worker_module, String.to_atom("Elixir.#{mod}"))
  end

  def after_processed_work(pipeline) do
    pipeline |> remove_job_from_backup
  end

  def after_failed_work(pipeline) do
    pipeline |> retry_or_fail_job |> remove_job_from_backup
  end


  defp retry_or_fail_job(%Pipeline{assigns: assigns} = pipeline) do
    if assigns.job do
      JobQueue.retry_or_fail_job(assigns.redis, assigns.namespace, assigns.job,
        to_string(assigns.error_message))
    end
    pipeline
  end

  def remove_job_from_backup(%Pipeline{assigns: assigns} = pipeline) do
    JobQueue.remove_job_from_backup(assigns.redis, assigns.namespace, assigns.host, assigns.queue,
      assigns.job_json)
    pipeline
  end
end
