defmodule Exq do
  require Logger
  use Application

  # Mixin Enqueue API
  use Exq.Enqueuer.EnqueueApi

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
  def stop(name) when is_atom(name) do
    case Process.whereis(Exq.Manager.Supervisor.supervisor_name(name)) do
      nil -> :ok
      pid ->
        stop(pid)
    end
  end

  @doc """
  Subscribe to a queue - ie. listen to queue for jobs
    * `pid` - PID for Exq Manager or Enqueuer to handle this
    * `queue` - Name of queue
    * `concurrency` - Optional argument specifying max concurrency for queue
  """
  def subscribe(pid, queue) do
    GenServer.call(pid, {:subscribe, queue})
  end
  def subscribe(pid, queue, concurrency) do
    GenServer.call(pid, {:subscribe, queue, concurrency})
  end

  @doc """
  Unsubscribe from a queue - ie. stop listening to queue for jobs
    * `pid` - PID for Exq Manager or Enqueuer to handle this
    * `queue` - Name of queue
  """
  def unsubscribe(pid, queue) do
    GenServer.call(pid, {:unsubscribe, queue})
  end

end
