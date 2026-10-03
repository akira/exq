defmodule Exq.Middleware.Behaviour do
  @moduledoc """
  Worker middleware configured through Exq's `:middleware` list.

  Lifecycle callbacks run in the worker GenServer, not the Task executing the job,
  and return the pipeline. Prefer `c:before_work/1`, `c:after_processed_work/1`,
  and `c:after_failed_work/1` for setup, cleanup, and notifications.

  Use the optional `c:around_perform/2` only when code must run inside the worker
  Task, such as attaching process-local context.
  """

  alias Exq.Middleware.Pipeline

  @doc """
  Runs in the worker GenServer before the worker Task starts.

  Prepare shared data in `pipeline.assigns`.
  """
  @callback before_work(%Pipeline{}) :: %Pipeline{}

  @doc """
  Runs in the worker GenServer after normal Task completion.

  `pipeline.assigns.result` contains the result returned by worker execution or
  its middleware.
  """
  @callback after_processed_work(%Pipeline{}) :: %Pipeline{}

  @doc """
  Runs in the worker GenServer when the Task raises, exits, is killed, or is canceled.

  `pipeline.assigns.error` and `pipeline.assigns.error_message` describe the failure.
  """
  @callback after_failed_work(%Pipeline{}) :: %Pipeline{}

  @doc """
  Wraps worker execution inside the Task, after job metadata is associated.

  Both `next.(pipeline)` and this callback return `{pipeline, result}`. The first
  configured middleware is outermost.

  Prefer the lifecycle callbacks unless Task-local execution is needed. Cleanup
  inside the Task is not guaranteed on hard kills or cancellation; use
  `c:after_failed_work/1` when cleanup must survive Task termination.

  After-work callbacks receive the returned assignments. On failure, they receive
  the last pipeline passed to `next` or returned by a completed callback.

  Returning without calling `next` is treated as normal completion.
  """
  @callback around_perform(%Pipeline{}, (%Pipeline{} -> {%Pipeline{}, term()})) ::
              {%Pipeline{}, term()}

  @optional_callbacks around_perform: 2
end
