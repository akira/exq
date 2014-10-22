defmodule Exq.Worker do 
  use GenServer
  require Record
  Record.defrecord :state, State, [:job]

  def start(job) do
    :gen_server.start(__MODULE__, {job}, [])
  end

  def work(pid) do 
    :gen_server.cast(pid, :work)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init({job}) do
    {:ok, state(job: job)}
  end

  def handle_cast(:work, my_state) do
    job_dict = JSEX.decode!(state(my_state, :job))
    target = Dict.get(job_dict, "class")
    [mod | func_or_empty] = Regex.split(~r/\//, target)
    func = case func_or_empty do
      [] -> :perform
      [f] -> :erlang.binary_to_atom(f, :utf8)
    end
    args = Dict.get(job_dict, "args")
    dispatch_work(mod, func, args)
    {:stop, :normal, my_state}
  end

  def code_change(_old_version, my_state, _extra) do
    {:ok, my_state}
  end

  def terminate(_reason, _state) do 
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
