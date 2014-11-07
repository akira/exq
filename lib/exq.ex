defmodule Exq do
  require Logger
  import Supervisor.Spec

  def start(opts \\ []) do
    Exq.Manager.Supervisor.start_link(opts)
  end

  def start_link(opts \\ []) do
    Exq.Manager.Supervisor.start_link(opts)
  end

  def stop(pid) do
    GenServer.call(pid, {:stop})
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

  def queues(pid) do
    :gen_server.call(pid, {:queues})
  end
  
  def jobs(pid) do
    :gen_server.call(pid, {:jobs})
  end

  def jobs(pid, queue) do
    :gen_server.call(pid, {:jobs, queue})
  end

  def queue_size(pid) do
    :gen_server.call(pid, {:queue_size})
  end

  def queue_size(pid, queue) do
    :gen_server.call(pid, {:queue_size, queue})
  end

  def find_failed(pid, jid) do
    GenServer.call(pid, {:find_failed, jid})
  end

  def find_job(pid, queue, jid) do
    GenServer.call(pid, {:find_job, queue, jid})
  end

end
