defmodule Exq.Middleware.Snooze do
  @behaviour Exq.Middleware.Behaviour
  alias Exq.Redis.JobQueue
  alias Exq.Middleware.Pipeline

  def before_work(pipeline) do
    pipeline
  end

  def after_processed_work(
        %Pipeline{assigns: %{result: {:snooze, seconds}} = assigns} =
          pipeline
      )
      when is_number(seconds) do
    if assigns.job do
      JobQueue.snooze_job(
        assigns.redis,
        assigns.namespace,
        assigns.job,
        seconds
      )
    end

    pipeline
  end

  def after_processed_work(pipeline) do
    pipeline
  end

  def after_failed_work(pipeline) do
    pipeline
  end
end
