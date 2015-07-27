defmodule Exq.Api do
  require Logger

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

  def jobs(pid, queue) do
    GenServer.call(pid, {:jobs, queue})
  end

  def failed(pid) do
    GenServer.call(pid, {:failed})
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

  def remove_queue(pid, queue) do
    GenServer.call(pid, {:remove_queue, queue})
  end

  def remove_failed(pid, jid) do
    GenServer.call(pid, {:remove_failed, jid})
  end

  def clear_failed(pid) do
    GenServer.call(pid, {:clear_failed})
  end

  def clear_processes(pid) do
    GenServer.call(pid, {:clear_processes})
  end

  def retry_failed(pid, jid) do
    GenServer.call(pid, {:retry_failed, jid})
  end

  def realtime_stats(pid) do
    GenServer.call(pid, {:realtime_stats})
  end

end
