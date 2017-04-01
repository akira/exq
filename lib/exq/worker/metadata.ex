defmodule Exq.Worker.Metadata do
  @moduledoc """
  Provides storage functionality for job metadata. The metadata is
  associated with the worker pid and automatically discarded when the
  worker process exits.
  """

  use GenServer
  alias Exq.Support.Config

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [name: server_name(opts[:name])])
  end

  def associate(server, pid, value) when is_pid(pid) do
    GenServer.call(server, {:associate, pid, value})
  end

  def lookup(server, pid) when is_pid(pid) do
    :ets.lookup_element(server, pid, 3)
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    table = :ets.new(server_name(opts[:name]), [:named_table])
    {:ok, table}
  end

  def handle_call({:associate, pid, value}, _from, table) do
    ref = Process.monitor(pid)
    true = :ets.insert(table, {pid, ref, value})
    {:reply, :ok, table}
  end

  def handle_info({:DOWN, ref, _type, pid, _reason}, table) do
    [{^pid, ^ref, _}] = :ets.lookup(table, pid)
    true = :ets.delete(table, pid)
    {:noreply, table}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end


  # Internal Functions

  def server_name(name) do
    name = name || Config.get(:name)
    "#{name}.Worker.Metadata" |> String.to_atom
  end
end
