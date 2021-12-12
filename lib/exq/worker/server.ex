defmodule Exq.Worker.Server do
  @moduledoc """
  Worker process is responsible for the parsing and execution of a Job.

  It then broadcasts results to Stats / Manager.

  Currently uses the `terminate` callback to track job success/failure.

  ## Initialization:
  * `job_serialized` - Full JSON payload of the Job.
  * `manager` - Manager process pid.
  * `queue` - The queue the job came from.
  * `stats` - Stats process pid.
  * `namespace` - Redis namespace
  * `host` - Host name

  Expects :work message after initialization to kickoff work.
  """
  use GenServer

  alias Exq.Middleware.Server, as: Middleware
  alias Exq.Middleware.Pipeline
  alias Exq.Worker.Metadata

  defmodule State do
    defstruct job_serialized: nil,
              manager: nil,
              queue: nil,
              namespace: nil,
              stats: nil,
              host: nil,
              redis: nil,
              middleware: nil,
              pipeline: nil,
              metadata: nil,
              middleware_state: nil
  end

  def start_link(
        job_serialized,
        manager,
        queue,
        stats,
        namespace,
        host,
        redis,
        middleware,
        metadata
      ) do
    GenServer.start_link(
      __MODULE__,
      {job_serialized, manager, queue, stats, namespace, host, redis, middleware, metadata},
      []
    )
  end

  @doc """
  Kickoff work associated with worker.
  """
  def work(pid) do
    GenServer.cast(pid, :work)
  end

  ## ===========================================================
  ## GenServer callbacks
  ## ===========================================================

  def init({job_serialized, manager, queue, stats, namespace, host, redis, middleware, metadata}) do
    {
      :ok,
      %State{
        job_serialized: job_serialized,
        manager: manager,
        queue: queue,
        stats: stats,
        namespace: namespace,
        host: host,
        redis: redis,
        middleware: middleware,
        metadata: metadata
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

    case state |> Map.fetch!(:pipeline) |> Map.get(:terminated, false) do
      # case done to run the after hooks
      true -> nil
      _ -> GenServer.cast(self(), :dispatch)
    end

    {:noreply, state}
  end

  # Dispatch work to the target module (call :perform method of target).
  def handle_cast(:dispatch, state) do
    dispatch_work(
      state.pipeline.assigns.worker_module,
      state.pipeline.assigns.job,
      state.metadata
    )

    {:noreply, state}
  end

  # Worker done with normal termination message.
  def handle_cast({:done, result}, state) do
    state =
      if !has_pipeline_after_work_ran?(state.pipeline) do
        %{state | pipeline: pipeline_after_processed_work(state, result)}
      else
        state
      end

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, _, _, :normal}, state) do
    state =
      if !has_pipeline_after_work_ran?(state.pipeline) do
        error = "Worker shutdown"
        %{state | pipeline: pipeline_after_failed_work(state, error, error)}
      else
        state
      end

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, _, error}, state) do
    error_message =
      error
      |> Inspect.Algebra.to_doc(%Inspect.Opts{})
      |> Inspect.Algebra.format(%Inspect.Opts{}.width)
      |> to_string

    state =
      if !has_pipeline_after_work_ran?(state.pipeline) do
        %{state | pipeline: pipeline_after_failed_work(state, error_message, error)}
      else
        state
      end

    {:stop, :normal, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  ## ===========================================================
  ## Internal Functions
  ## ===========================================================

  def dispatch_work(worker_module, job, metadata) do
    # trap exit so that link can still track dispatch without crashing
    Process.flag(:trap_exit, true)
    worker = self()

    {:ok, pid} =
      Task.start_link(fn ->
        :ok = Metadata.associate(metadata, self(), job)
        result = apply(worker_module, :perform, job.args)
        GenServer.cast(worker, {:done, result})
      end)

    Process.monitor(pid)
  end

  defp before_work(state) do
    %Pipeline{event: :before_work, worker_pid: self()}
    |> Pipeline.assign_worker_state(state)
    |> Pipeline.chain(state.middleware_state)
  end

  defp pipeline_after_processed_work(state, result) do
    %Pipeline{event: :after_processed_work, worker_pid: self(), assigns: state.pipeline.assigns}
    |> Pipeline.assign(:result, result)
    |> Pipeline.chain(state.middleware_state)
  end

  defp pipeline_after_failed_work(state, error_message, error) do
    %Pipeline{event: :after_failed_work, worker_pid: self(), assigns: state.pipeline.assigns}
    |> Pipeline.assign(:error_message, error_message)
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(state.middleware_state)
  end

  defp has_pipeline_after_work_ran?(pipeline) do
    Map.has_key?(pipeline, :result) || Map.has_key?(pipeline, :error)
  end
end
