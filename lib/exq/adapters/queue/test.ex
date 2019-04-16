defmodule Exq.Adapters.Queue.Test do
  @moduledoc false

  @behaviour Exq.Adapters.Queue

  def enqueue(_pid, _queue, worker, args, _options) do
    {:ok, apply(worker, :perform, args)}
  end

  def enqueue(pid, _from, queue, worker, args, options) do
    enqueue(pid, queue, worker, args, options)
  end

  def enqueue_at(pid, queue, _time, worker, args, options) do
    enqueue(pid, queue, worker, args, options)
  end

  def enqueue_at(pid, _from, queue, _time, worker, args, options) do
    enqueue(pid, queue, worker, args, options)
  end

  def enqueue_in(pid, queue, _offset, worker, args, options) do
    enqueue(pid, queue, worker, args, options)
  end

  def enqueue_in(pid, _from, queue, _offset, worker, args, options) do
    enqueue(pid, queue, worker, args, options)
  end
end
