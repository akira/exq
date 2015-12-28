defmodule Exq.Worker.Server do
  require Logger
  use GenServer

  alias Exq.Stats.Server, as: Stats

  defmodule State do
    defstruct job_json: nil, job: nil, manager: nil, queue: nil, namespace: nil,
      work_table: nil, worker_module: nil, worker_function: nil, stats: nil, host: nil,
      process_info: nil
  end

  def start(job_json, manager, queue, work_table, stats, namespace, host) do
    GenServer.start(__MODULE__, {job_json, manager, queue, work_table, stats, namespace, host}, [])
  end

  def work(pid) do
    GenServer.cast(pid, :work)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init({job_json, manager, queue, work_table, stats, namespace, host}) do
    {
      :ok,
      %State{
        job_json: job_json, manager: manager, queue: queue,
        work_table: work_table, stats: stats, namespace: namespace, host: host
      }
    }
  end

  def handle_cast(:work, state) do
    {:ok, process_info} = Stats.add_process(state.stats, state.namespace, self(), state.host, state.job_json)
    job = Exq.Support.Job.from_json(state.job_json)
    target = String.replace(job.class, "::", ".")
    [mod | _func_or_empty] = Regex.split(~r/\//, target)
    func = :perform
    GenServer.cast(self, :dispatch)
    {:noreply, %{state | worker_module: String.to_atom("Elixir.#{mod}"),
                 worker_function: func, job: job, process_info: process_info } }
  end

  def handle_cast(:dispatch, state) do
    dispatch_work(state.worker_module, state.worker_function, state.job.args)
    {:stop, :normal, state }
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(:normal, %State{manager: nil}), do: :ok

  def terminate(:normal, state) do
    case Process.alive?(state.manager) do
      true ->
        Exq.Manager.Server.job_terminated(state.manager, state.namespace, state.queue, state.job_json)
        Stats.process_terminated(state.stats, state.namespace, state.process_info)
        Stats.record_processed(state.stats, state.namespace, state.job)
      _ ->
        Logger.error("Worker terminated, but manager was not alive.")
    end
    :ok
  end

  def terminate(_error, %State{manager: nil}), do: :ok

  def terminate(error, state) do
    case Process.alive?(state.manager) do
      true ->
        Exq.Manager.Server.job_terminated(state.manager, state.namespace, state.queue, state.job_json)
        Stats.process_terminated(state.stats, state.namespace, state.process_info)
        error_msg = Inspect.Algebra.format(Inspect.Algebra.to_doc(error, %Inspect.Opts{}), %Inspect.Opts{}.width)
        Stats.record_failure(state.stats, state.namespace, to_string(error_msg), state.job)
        Logger.error("Worker terminated, #{error_msg}")
      _ ->
        Logger.error("Worker terminated, but manager was not alive.")
    end
    :ok
  end

##===========================================================
## Internal Functions
##===========================================================

  def dispatch_work(worker_module, args) do
    dispatch_work(worker_module, :perform, args)
  end
  def dispatch_work(worker_module, method, args) do
    apply(worker_module, method, args)
  end
end
