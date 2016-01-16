defmodule Exq do
  require Logger
  use Application

  import Exq.Opts

  # Mixin Enqueue API
  use Exq.Enqueuer.EnqueueApi

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    start_link
  end

  # Exq methods
  def start_link(opts \\ []) do
    import Supervisor.Spec, warn: false

    {redis_opts, connection_opts, opts} = conform_opts(opts)

    # make sure redis always first(start in order)
    children = [
      worker(Redix, [redis_opts, connection_opts]),
      worker(Exq.Stats.Server, [opts]),
      worker(Exq.Enqueuer.Server, [opts]),
      supervisor(Exq.Worker.Supervisor, [opts]),
      worker(Exq.Manager.Server, [opts]),
    ]

    if opts[:scheduler_enable] do
      children = children ++ [worker(Exq.Scheduler.Server, [opts])]
    end

    Supervisor.start_link(children,
      name: top_supervisor(opts[:name]),
      strategy: :one_for_one,
      max_restarts: 20,
      max_seconds: 5)
  end

  # todo refactor better
  def stop(pid) when is_pid(pid) do
    Process.exit(pid, :shutdown)
  end
  def stop(name) when is_atom(name) do
    case Process.whereis(top_supervisor(name)) do
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
