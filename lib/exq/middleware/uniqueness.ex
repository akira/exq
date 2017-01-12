defmodule Exq.Middleware.Uniqueness do
  @behaviour Exq.Middleware.Behaviour
  alias Exq.Middleware.Pipeline
  import Exq.Enqueuer.Uniqueness, only: [remove_key: 2, hash_string: 1, remove_locks: 1]

  def before_work(pipeline), do: pipeline

  def after_processed_work(pipeline) do
    pipeline |> remove_locks
  end

  def after_failed_work(pipeline) do
    pipeline |> remove_unique_lock_unless_retry
  end

  defp remove_unique_lock_unless_retry(pipeline) do
    case pipeline.retry do
      false -> pipeline
      _     -> remove_locks pipeline
    end
  end
end
