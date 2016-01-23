defmodule Exq.Middleware.Logger do
  @behaviour Exq.Middleware.Behaviour

  alias Exq.Middleware.Pipeline
  import Pipeline
  use Timex
  require Logger

  def before_work(pipeline) do
    Logger.info("#{log_context(pipeline)} start")
    assign(pipeline, :started_at, Time.now)
  end

  def after_processed_work(pipeline) do
    Logger.info("#{log_context(pipeline)} done: #{delta(pipeline)} sec")
    pipeline
  end

  def after_failed_work(pipeline) do
    Logger.info(to_string(pipeline.assigns.error_message))
    Logger.info("#{log_context(pipeline)} fail: #{delta(pipeline)} sec")
    pipeline
  end


  defp delta(%Pipeline{assigns: assigns} = pipeline) do
    Time.diff(Time.now, assigns.started_at, :secs)
  end

  defp log_context(%Pipeline{assigns: assigns} = pipeline) do
    "#{assigns.worker_module}[#{assigns.job.jid}]"
  end
end
