defmodule Exq.Middleware.Manager do
  @behaviour Exq.Middleware.Behaviour
  require Logger
  alias Exq.Manager.Server, as: Manager
  alias Exq.Middleware.Pipeline

  def before_work(pipeline) do
    pipeline
  end

  def after_processed_work(pipeline) do
    pipeline |> notify(true)
  end

  def after_failed_work(pipeline) do
    pipeline |> notify(false)
  end

  defp notify(%Pipeline{assigns: assigns} = pipeline, success) do
    Manager.job_terminated(
      assigns.manager,
      assigns.queue,
      success
    )

    pipeline
  end
end
