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

  def stop(pid) do
    GenServer.call(pid, {:stop})
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

end
