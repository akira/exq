defmodule Exq.Worker do 
  require Logger
  use GenServer
  
  defmodule State do
    defstruct job: nil, manager: nil
  end

  def start(job, manager \\ nil) do
    :gen_server.start(__MODULE__, {job, manager}, [])
  end

  def work(pid) do 
    :gen_server.cast(pid, :work)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init({job, manager}) do
    {:ok, %State{job: job, manager: manager}}
  end

  def handle_cast(:work, state) do
    job = Poison.decode!(state.job, as: Exq.Job)
    target = job.class
    [mod | func_or_empty] = Regex.split(~r/\//, target)
    func = case func_or_empty do
      [] -> :perform
      [f] -> :erlang.binary_to_atom(f, :utf8)
    end
    args = job.args
    dispatch_work(mod, func, args)
    {:stop, :normal, state}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(:normal, %State{manager: nil}), do: :ok

  def terminate(:normal, state) do
    case Process.alive?(state.manager) do
      true ->
        :gen_server.call(state.manager, {:success, state.job})
      _ ->
        Logger.error("Worker terminated, but manager was not alive.")
    end
    :ok
  end

  def terminate(error, %State{manager: nil}), do: :ok

  def terminate(error, state) do
    case Process.alive?(state.manager) do
      true ->
        error_msg = Inspect.Algebra.format(Inspect.Algebra.to_doc(error, %Inspect.Opts{}), %Inspect.Opts{}.width)
        :gen_server.call(state.manager, {:failure, to_string(error_msg), state.job})
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
    :erlang.apply(String.to_atom("Elixir.#{worker_module}"), method, args)
  end
end
