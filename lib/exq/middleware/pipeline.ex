defmodule Exq.Middleware.Pipeline do
  @moduledoc """
  Pipeline is a structure that is used as an argument in functions of module with
  `Exq.Middleware.Behaviour` behaviour.

  This structure must be returned by particular function to be used in the next
  middleware based on defined middleware chain.

  Pipeline contains the following options:

  * `assigns` - map that contains shared data across the whole job lifecycle
  * `worker_pid` - process id of `Exq.Worker.Server`
  * `event` - name of current middleware function, possible values are: `before_work`,
  `after_processed_work` and `after_failed_work`
  * `halted` - flag indicating whether pipeline was halted, defaults to `false`
  * `terminated` - flag indicating whether worker and pipeline were halted, If
      the flag was set to true, the job will not be dispatched and all after_*_work/1
      will be skipped. For each specific middleware:
      - Exq.Middleware.Job: Will NOT remove the backup from job queue
      - Exq.Middleware.Logger: Will NOT record job as done or failed with timestamp
      - Exq.Middleware.Manager: Will NOT update worker counter
      - Exq.Middleware.Unique: Will NOT clear unique lock
      - Exq.Middleware.Stats: Will NOT remove job from processes queue

  """

  defstruct assigns: %{},
            halted: false,
            terminated: false,
            worker_pid: nil,
            event: nil

  alias Exq.Middleware.Pipeline

  @doc """
  Puts the `key` with value equal to `value` into `assigns` map
  """
  def assign(%Pipeline{assigns: assigns} = pipeline, key, value) when is_atom(key) do
    %{pipeline | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Sets `halted` to true
  """
  def halt(%Pipeline{} = pipeline) do
    %{pipeline | halted: true}
  end

  @doc """
  Sets `terminated` to true
  """
  def terminate(%Pipeline{} = pipeline) do
    %{pipeline | terminated: true}
  end

  @doc """
  Puts a state of `Exq.Worker.Server` into `assigns` map
  """
  def assign_worker_state(pipeline, worker_state) do
    pipeline
    |> assign(:redis, worker_state.redis)
    |> assign(:host, worker_state.host)
    |> assign(:namespace, worker_state.namespace)
    |> assign(:queue, worker_state.queue)
    |> assign(:manager, worker_state.manager)
    |> assign(:stats, worker_state.stats)
    |> assign(:job_serialized, worker_state.job_serialized)
  end

  @doc """
  Implements middleware chain: sequential call of function with `pipeline.event` name inside `module` module
  """
  def chain(pipeline, []) do
    pipeline
  end

  def chain(%Pipeline{halted: true} = pipeline, _modules) do
    pipeline
  end

  def chain(%Pipeline{terminated: true} = pipeline, _modules) do
    pipeline
  end

  def chain(pipeline, [module | modules]) do
    chain(apply(module, pipeline.event, [pipeline]), modules)
  end
end
