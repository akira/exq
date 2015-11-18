defmodule Exq.Worker.Server do
  require Logger
  use GenServer

  defmodule State do
    defstruct job_json: nil, job: nil, manager: nil, queue: nil, work_table: nil, worker_module: nil, worker_function: nil
  end

  def start(job_json, manager, queue, work_table) do
    GenServer.start(__MODULE__, {job_json, manager, queue, work_table}, [])
  end

  def work(pid) do
    GenServer.cast(pid, :work)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init({job_json, manager, queue, work_table}) do
    {:ok, %State{job_json: job_json, manager: manager, queue: queue, work_table: work_table}}
  end

  def handle_cast(:work, state) do
    job = Exq.Support.Job.from_json(state.job_json)

    target = String.replace(job.class, "::", ".")
    [mod | func_or_empty] = Regex.split(~r/\//, target)
    func = :perform
    args = job.args
    GenServer.cast(self, :dispatch)
    {:noreply, %{state | worker_module: String.to_atom("Elixir.#{mod}"), worker_function: func, job: job} }
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
        GenServer.cast(state.manager, {:worker_terminated, self()})
        GenServer.cast(state.manager, {:success, state.job})
        Exq.Manager.Server.update_worker_count(state.work_table, state.queue, -1)
      _ ->
        Logger.error("Worker terminated, but manager was not alive.")
    end
    :ok
  end

  def terminate(_error, %State{manager: nil}), do: :ok

  def terminate(error, state) do
    case Process.alive?(state.manager) do
      true ->
        GenServer.cast(state.manager, {:worker_terminated, self()})
        error_msg = Inspect.Algebra.format(Inspect.Algebra.to_doc(error, %Inspect.Opts{}), %Inspect.Opts{}.width)
        GenServer.cast(state.manager, {:failure, to_string(error_msg), state.job})
        Exq.Manager.Server.update_worker_count(state.work_table, state.queue, -1)
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
