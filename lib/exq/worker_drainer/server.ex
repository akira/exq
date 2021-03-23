defmodule Exq.WorkerDrainer.Server do
  @moduledoc """
  The WorkerDrainer server is responsible for gracefully draining
  workers when the application is shutting down.

  When shutdown starts it instructs the Manager to stop accepting new jobs and
  then waits for all currently in progress jobs to complete.

  If the jobs do not complete within an allowed timeout the WorkerDrainer
  will shut down, allowing the rest of the supervision tree (including the
  remaining workers) to then shut down.

  The length of the grace period can be configured with the
  `shutdown_timeout` option, which defaults to 5000 ms.
  """

  use GenServer
  alias Exq.{Worker, Manager}

  defstruct name: Exq,
            shutdown_timeout: 5000

  def server_name(name) do
    name = name || Exq.Support.Config.get(:name)
    "#{name}.WorkerDrainer" |> String.to_atom()
  end

  ## ===========================================================
  ## GenServer callbacks
  ## ===========================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  def init(opts) do
    Process.flag(:trap_exit, true)
    state = struct(__MODULE__, opts)
    {:ok, state}
  end

  def terminate(:shutdown, state) do
    drain_workers(state)
  end

  def terminate({:shutdown, _}, state) do
    drain_workers(state)
  end

  def terminate(:normal, state) do
    drain_workers(state)
  end

  def terminate(_, _) do
    :ok
  end

  ## ===========================================================
  ## Internal Functions
  ## ===========================================================

  defp drain_workers(state) do
    timer_ref = :erlang.start_timer(state.shutdown_timeout, self(), :end_of_grace_period)

    :ok =
      state.name
      |> Manager.Server.server_name()
      |> Exq.unsubscribe_all()

    state.name
    |> Worker.Supervisor.supervisor_name()
    |> Worker.Supervisor.workers()
    |> Enum.map(&Process.monitor(elem(&1, 1)))
    |> Enum.into(MapSet.new())
    |> await_workers(timer_ref)
  end

  defp await_workers(%{map: refs}, _) when map_size(refs) == 0 do
    :ok
  end

  defp await_workers(worker_refs, timer_ref) do
    receive do
      {:DOWN, downed_ref, _, _, _} ->
        worker_refs
        |> MapSet.delete(downed_ref)
        |> await_workers(timer_ref)

      # Not all workers finished within grace period
      {:timeout, ^timer_ref, :end_of_grace_period} ->
        :ok
    end
  end
end
