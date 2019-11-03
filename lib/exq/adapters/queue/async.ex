defmodule Exq.Adapters.Queue.Async do
  @moduledoc """
  Asynchronous queue. Enqueue the job by using the GenServer API.

  Default queue. Designed to be used in production.
  """
  alias Exq.Support.Config
  alias Exq.Redis.JobQueue

  @behaviour Exq.Adapters.Queue

  def enqueue(pid, queue, worker, args, options) do
    {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
    JobQueue.enqueue(redis, namespace, queue, worker, args, options)
  end

  def enqueue_at(pid, queue, time, worker, args, options) do
    {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
    JobQueue.enqueue_at(redis, namespace, queue, time, worker, args, options)
  end

  def enqueue_in(pid, queue, offset, worker, args, options) do
    {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
    JobQueue.enqueue_in(redis, namespace, queue, offset, worker, args, options)
  end
end
