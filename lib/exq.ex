defmodule Exq do
  require Logger
  alias Exq.Support.Config
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

  @doc """
  Enqueue a job immediately.

  Expected args:
    * `pid` - PID for Exq Manager or Enqueuer to handle this
    * `queue` - Name of queue to use
    * `worker` - Worker module to target
    * `args` - Array of args to send to worker

  Returns:
  * `{:ok, jid}` if the job was enqueued successfully, with `jid` = Job ID.
  * `{:error, reason}` if there was an error enqueueing job
  """
  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args}, Config.get(:genserver_timeout, 5000))
  end

  @doc """
  Schedule a job to be enqueued at a specific time in the future.

  Expected args:
    * `pid` - PID for Exq Manager or Enqueuer to handle this
    * `queue` - name of queue to use
    * `time` - Time to enqueue
    * `worker` - Worker module to target
    * `args` - Array of args to send to worker
  """
  def enqueue_at(pid, queue, time, worker, args) do
    GenServer.call(pid, {:enqueue_at, queue, time, worker, args}, Config.get(:genserver_timeout, 5000))
  end

  @doc """
  Schedule a job to be enqueued at in the future given by offset in milliseconds.

  Expected args:
    * `pid` - PID for Exq Manager or Enqueuer to handle this
    * `queue` - Name of queue to use
    * offset - Offset in milliseconds in the future to enqueue
    * `worker` - Worker module to target
    * `args` - Array of args to send to worker
  """
  def enqueue_in(pid, queue, offset, worker, args) do
    GenServer.call(pid, {:enqueue_in, queue, offset, worker, args}, Config.get(:genserver_timeout, 5000))
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
