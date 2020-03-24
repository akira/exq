defmodule Exq.Support.Mode do
  @moduledoc """
  This module defines several modes in which Exq can be used. These modes are:

  * `default` - starts the default processes
  * `enqueuer` - starts processes which are responsible for job enqueueing
  * `api` - starts processes which are responsible for API usage
  """

  @doc """
  Returns child list for the main Exq supervisor
  """

  import Exq.Support.Opts, only: [redis_worker_opts: 1]
  import Supervisor.Spec

  def children(opts) do
    {module, args, opts} = redis_worker_opts(opts)
    # make sure redis always first(start in order)
    children = [worker(module, args)]
    children = children ++ children(opts[:mode], opts)
    children
  end

  def children(:default, opts) do
    shutdown_timeout = Keyword.get(opts, :shutdown_timeout)

    children = [
      worker(Exq.Worker.Metadata, [opts]),
      worker(Exq.Middleware.Server, [opts]),
      worker(Exq.Stats.Server, [opts]),
      supervisor(Exq.Worker.Supervisor, [opts]),
      worker(Exq.Manager.Server, [opts]),
      worker(Exq.WorkerDrainer.Server, [opts], shutdown: shutdown_timeout),
      worker(Exq.Enqueuer.Server, [opts]),
      worker(Exq.Api.Server, [opts])
    ]

    children =
      if opts[:scheduler_enable] do
        children ++ [worker(Exq.Scheduler.Server, [opts])]
      else
        children
      end

    if opts[:heartbeat_enable] do
      children ++ [worker(Exq.Heartbeat.Server, [opts]), worker(Exq.Heartbeat.Monitor, [opts])]
    else
      children
    end
  end

  def children(:enqueuer, opts) do
    [worker(Exq.Enqueuer.Server, [opts])]
  end

  def children(:api, opts) do
    [worker(Exq.Api.Server, [opts])]
  end

  def children([:enqueuer, :api], opts) do
    [
      worker(Exq.Enqueuer.Server, [opts]),
      worker(Exq.Api.Server, [opts])
    ]
  end

  def children([:api, :enqueuer], opts), do: children([:enqueuer, :api], opts)
end
