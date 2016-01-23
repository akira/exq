defmodule Exq.Middleware.Pipeline do
  @moduledoc """
  Pipeline is a structure that is used as an argument in functions of module with
  `Exq.Middleware.Behaviour` behaviour. This structure must be returned by particular function
  to be used in the next middleware based on defined middleware chain.

  Pipeline contains the following options:

  * `assigns` - map that contains shared data across the whole job lifecycle
  * `worker_pid` - process id of `Exq.Worker.Server`
  * `event` - name of current middleware function, possible values are: `before_work`,
  `after_processed_work` and `after_failed_work`
  * `halted` - flag indicating whether pipeline was halted, defaults to `false`
  """

  defstruct assigns:      %{},
            halted:       false,
            worker_pid:   nil,
            event:        nil

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
  Puts a state of `Exq.Worker.Server` into `assigns` map
  """
  def assign_worker_state(pipeline, worker_state) do
    pipeline
    |> assign(    :redis, worker_state.redis)
    |> assign(     :host, worker_state.host)
    |> assign(:namespace, worker_state.namespace)
    |> assign(    :queue, worker_state.queue)
    |> assign(  :manager, worker_state.manager)
    |> assign(    :stats, worker_state.stats)
    |> assign( :job_json, worker_state.job_json)
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
  def chain(pipeline, [module|modules]) do
    chain(apply(module, pipeline.event, [pipeline]), modules)
  end
end
