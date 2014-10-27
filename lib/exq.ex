defmodule Exq do
  require Logger
  def start(opts \\ []) do
    :gen_server.start(Exq.Manager, opts, [])
  end

  def start_link(opts \\ []) do
    {:ok, pid} = :gen_server.start_link(Exq.Manager, opts, [])
  end

  def stop(pid) do
    :gen_server.call(pid, {:stop})
  end

  def enqueue(pid, queue, worker, args) do 
    :gen_server.call(pid, {:enqueue, queue, worker, args})
  end

  def find_failed(pid, jid) do
    :gen_server.call(pid, {:find_failed, jid})
  end

  def find_job(pid, queue, jid) do
    :gen_server.call(pid, {:find_job, queue, jid})
  end

end
