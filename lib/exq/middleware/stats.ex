defmodule Exq.Middleware.Stats do
  @behaviour Exq.Middleware.Behaviour
  require Logger
  alias Exq.Stats.Server, as: Stats
  alias Exq.Middleware.Pipeline
  import Pipeline

  def before_work(pipeline) do
    {:ok, info} = add_process(pipeline)
    assign(pipeline, :process_info, info)
  end

  def after_processed_work(pipeline) do
    pipeline |> process_terminated |> record_processed
  end

  def after_failed_work(pipeline) do
    pipeline |> process_terminated |> record_failure
  end

  defp add_process(%Pipeline{assigns: assigns, worker_pid: worker_pid}) do
    Stats.add_process(
      assigns.stats,
      assigns.namespace,
      worker_pid,
      assigns.host,
      assigns.queue,
      assigns.job_serialized
    )
  end

  defp process_terminated(%Pipeline{assigns: assigns} = pipeline) do
    Stats.process_terminated(assigns.stats, assigns.namespace, assigns.process_info)
    pipeline
  end

  defp record_processed(%Pipeline{assigns: assigns} = pipeline) do
    Stats.record_processed(assigns.stats, assigns.namespace, assigns.job)
    pipeline
  end

  defp record_failure(%Pipeline{assigns: assigns} = pipeline) do
    Stats.record_failure(
      assigns.stats,
      assigns.namespace,
      to_string(assigns.error_message),
      assigns.job
    )

    pipeline
  end
end
