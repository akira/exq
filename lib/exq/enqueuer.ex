defmodule Exq.Enqueuer do

  def start(opts \\ []) do
    Exq.Enqueuer.Supervisor.start_link(opts)
  end

  def start_link(opts \\ []) do
    Exq.Enqueuer.Supervisor.start_link(opts)
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

  # Sync call, replies to "from" sender
  def enqueue(pid, from, queue, worker, args) do
    GenServer.cast(pid, {:enqueue, from, queue, worker, args})
  end

  def enqueue_at(pid, queue, time, worker, args) do
    GenServer.call(pid, {:enqueue_at, queue, time, worker, args})
  end

  # Sync call, replies to "from" sender
  def enqueue_at(pid, from, queue, time, worker, args) do
    GenServer.cast(pid, {:enqueue_at, from, queue, time, worker, args})
  end

  def enqueue_in(pid, queue, offset, worker, args) do
    GenServer.call(pid, {:enqueue_in, queue, offset, worker, args})
  end

  # Sync call, replies to "from" sender
  def enqueue_in(pid, from, queue, offset, worker, args) do
    GenServer.cast(pid, {:enqueue_in, from, queue, offset, worker, args})
  end

  def queues(pid) do
    GenServer.call(pid, {:queues})
  end

  def busy(pid) do
    GenServer.call(pid, {:busy})
  end

  def stats(pid, key) do
    GenServer.call(pid, {:stats, key})
  end

  def stats(pid, key, date) do
    GenServer.call(pid, {:stats, key, date})
  end

  def processes(pid) do
    GenServer.call(pid, {:processes})
  end

  def jobs(pid) do
    GenServer.call(pid, {:jobs})
  end
  def jobs(pid, :scheduled) do
    GenServer.call(pid, {:jobs, :scheduled})
  end
  def jobs(pid, queue) do
    GenServer.call(pid, {:jobs, queue})
  end

  def queue_size(pid) do
    GenServer.call(pid, {:queue_size})
  end
  def queue_size(pid, :scheduled) do
    GenServer.call(pid, {:queue_size, :scheduled})
  end
  def queue_size(pid, queue) do
    GenServer.call(pid, {:queue_size, queue})
  end

  def find_failed(pid, jid) do
    GenServer.call(pid, {:find_failed, jid})
  end

  def find_job(pid, queue, jid) do
    GenServer.call(pid, {:find_job, queue, jid})
  end

  def stop(pid) do
    GenServer.call(pid, {:stop})
  end
end
