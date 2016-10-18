defmodule Exq.Middleware.Manager do
  @behaviour Exq.Middleware.Behaviour
  require Logger
  alias Exq.Manager.Server, as: Manager
  alias Exq.Middleware.Pipeline

  def before_work(pipeline) do
    pipeline
  end

  def after_processed_work(pipeline) do
    pipeline |> notify
  end

  def after_failed_work(pipeline) do
    pipeline |> notify
  end


  defp notify(%Pipeline{assigns: assigns} = pipeline) do
    Manager.job_terminated(assigns.manager, assigns.namespace, assigns.queue, assigns.job_serialized)
    pipeline
  end
end
