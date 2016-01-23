defmodule Exq.Worker.Server do
  @moduledoc """
  Worker process is responsible for the parsing and execution of a Job. It then
  broadcasts results to Stats / Manager.

  Currently uses the `terminate` callback to track job success/failure .

  ## Initialization:
    * `job_json` - Full JSON payload of the Job.
    * `manager` - Manager process pid.
    * `queue` - The queue the job came from.
    * `:work_table` - In process work ets table (TODO: Remove).
    * `stats` - Stats process pid.
    * `namespace` - Redis namespace
    * `host` - Host name

  Expects :work message after initialization to kickoff work.
  """
  use GenServer

  alias Exq.Middleware.Server, as: Middleware
  alias Exq.Middleware.Pipeline

  defmodule State do
    defstruct job_json: nil, manager: nil, queue: nil, namespace: nil,
      work_table: nil, stats: nil, host: nil, redis: nil, middleware: nil, pipeline: nil,
      middleware_state: nil
  end

  def start_link(job_json, manager, queue, work_table, stats, namespace, host, redis, middleware) do
    GenServer.start(__MODULE__, {job_json, manager, queue, work_table, stats, namespace, host, redis, middleware}, [])
  end

  @doc """
  Kickoff work associated with worker.
  """
  def work(pid) do
    GenServer.cast(pid, :work)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init({job_json, manager, queue, work_table, stats, namespace, host, redis, middleware}) do
    {
      :ok,
      %State{
        job_json: job_json, manager: manager, queue: queue,
        work_table: work_table, stats: stats, namespace: namespace,
        host: host, redis: redis, middleware: middleware
      }
    }
  end
  @doc """
  Kickoff work associated with worker.

  This step handles:
    * Parsing of JSON object
    * Preparation of target module

  Calls :dispatch to then call target module.
  """
  def handle_cast(:work, state) do
    state = %{state | middleware_state: Middleware.all(state.middleware)}
    state = %{state | pipeline: before_work(state)}
    GenServer.cast(self, :dispatch)
    {:noreply, state}
  end


  @doc """
  Dispatch work to the target module (call :perform method of target)
  """
  def handle_cast(:dispatch, state) do
    dispatch_work(state.pipeline.assigns.worker_module, state.pipeline.assigns.job.args)
    {:noreply, state }
  end

  @doc """
  Worker done with normal termination message
  """
  def handle_cast(:done, state) do
    after_processed_work(state)
    {:stop, :normal, state }
  end

  def handle_info({:DOWN, _, _, _, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _, error}, state) do
    error_message = error
    |> Inspect.Algebra.to_doc(%Inspect.Opts{})
    |> Inspect.Algebra.format(%Inspect.Opts{}.width)
    |> to_string

    after_failed_work(state, error_message)
    {:stop, :normal, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

##===========================================================
## Internal Functions
##===========================================================

  def dispatch_work(worker_module, args) do
    # trap exit so that link can still track dispatch without crashing
    Process.flag(:trap_exit, true)
    worker = self
    pid = spawn_link fn ->
      apply(worker_module, :perform, args)
      GenServer.cast(worker, :done)
    end
    Process.monitor(pid)
  end

  defp before_work(state) do
    %Pipeline{event: :before_work, worker_pid: self}
    |> Pipeline.assign_worker_state(state)
    |> Pipeline.chain(state.middleware_state)
  end

  defp after_processed_work(state) do
    %Pipeline{event: :after_processed_work, worker_pid: self, assigns: state.pipeline.assigns}
    |> Pipeline.chain(state.middleware_state)
  end

  defp after_failed_work(state, error_message) do
    %Pipeline{event: :after_failed_work, worker_pid: self, assigns: state.pipeline.assigns}
    |> Pipeline.assign(:error_message, error_message)
    |> Pipeline.chain(state.middleware_state)
  end
end
