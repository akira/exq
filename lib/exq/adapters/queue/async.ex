defmodule Exq.Adapters.Queue.Async do
  @moduledoc """
  Asynchronous queue. Enqueue the job by using the GenServer API.

  Default queue. Designed to be used in production.
  """
  alias Exq.Support.Config

  @behaviour Exq.Adapters.Queue

  def enqueue(pid, queue, worker, args, options) do
    GenServer.call(
      pid,
      {:enqueue, queue, worker, args, options},
      Config.get(:genserver_timeout)
    )
  end

  def enqueue(pid, from, queue, worker, args, options) do
    GenServer.cast(pid, {:enqueue, from, queue, worker, args, options})
  end

  def enqueue_at(pid, queue, time, worker, args, options) do
    GenServer.call(
      pid,
      {:enqueue_at, queue, time, worker, args, options},
      Config.get(:genserver_timeout)
    )
  end

  def enqueue_at(pid, from, queue, time, worker, args, options) do
    GenServer.cast(pid, {:enqueue_at, from, queue, time, worker, args, options})
  end

  def enqueue_in(pid, queue, offset, worker, args, options) do
    GenServer.call(
      pid,
      {:enqueue_in, queue, offset, worker, args, options},
      Config.get(:genserver_timeout)
    )
  end

  def enqueue_in(pid, from, queue, offset, worker, args, options) do
    GenServer.cast(pid, {:enqueue_in, from, queue, offset, worker, args, options})
  end
end
