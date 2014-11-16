defmodule Exq do
  require Logger
  import Supervisor.Spec
  use Application

  # OTP Application
  def start(_type, _args) do
    Exq.Manager.Supervisor.start_link
  end

  # Exq methods

  def start(opts \\ []) do
    Exq.Manager.Supervisor.start_link(opts)
  end

  def start_link(opts \\ []) do
    Exq.Manager.Supervisor.start_link(opts)
  end

  def stop(pid) when is_pid(pid) do
    Process.exit(pid, :shutdown)
  end
  def stop(sup) when is_atom(sup) do
    stop(Process.whereis(sup))
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

end
