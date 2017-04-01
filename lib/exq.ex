defmodule Exq do
  require Logger
  use Application

  import Exq.Support.Opts, only: [top_supervisor: 1]
  alias Exq.Worker.Metadata

  # Mixin Enqueue API
  use Exq.Enqueuer.EnqueueApi

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    start_link()
  end

  # Exq methods
  def start_link(opts \\ []) do
    children = Exq.Support.Mode.children(opts)

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


  @doc """
  Get the job metadata
    * `name` - registered name of Exq. Only necessary if the custom
      name option is used when starting Exq. Defaults to Exq
    * `pid` - pid of the worker. Defaults to self().
  """
  def worker_job(name \\ nil, pid \\ self()) do
    metadata = Metadata.server_name(name)
    Metadata.lookup(metadata, pid)
  end
end
