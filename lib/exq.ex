defmodule Exq do
  require Logger
  def start(opts \\ []) do
    GenServer.start(Exq.Manager, opts, [])
  end

  def start_link(opts \\ []) do
    {:ok, pid} = GenServer.start_link(Exq.Manager, opts, [])
  end

  def stop(pid) do
    GenServer.call(pid, {:stop})
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

  def find_failed(pid, jid) do
    GenServer.call(pid, {:find_failed, jid})
  end

  def find_job(pid, queue, jid) do
    GenServer.call(pid, {:find_job, queue, jid})
  end

end
