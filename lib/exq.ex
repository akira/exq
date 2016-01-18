defmodule Exq do
  require Logger
  use Application

  import Exq.Support.Opts

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
      worker(Exq.Middleware.Server, [opts]),
      worker(Exq.Manager.Server, [opts]),
      worker(Exq.Stats.Server, [opts]),
      worker(Exq.Enqueuer.Server, [opts]),
      supervisor(Exq.Worker.Supervisor, [opts])
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

  def stop(nil), do: :ok
  def stop(pid) when is_pid(pid), do: Process.exit(pid, :shutdown)
  def stop(name) do
      name
      |> top_supervisor
      |> Process.whereis
      |> stop
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
