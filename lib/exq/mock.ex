defmodule Exq.Mock do
  alias Exq.Support.Config
  alias Exq.Adapters.Queue.Redis
  use GenServer
  @timeout 30000

  defmodule State do
    defstruct default_mode: :redis, jobs: %{}, modes: %{}
  end

  ### Public api

  def start_link(options \\ []) do
    queue_adapter = Config.get(:queue_adapter)

    if queue_adapter != Exq.Adapters.Queue.Mock do
      raise RuntimeError, """
      Exq.Mock can only work if queue_adapter is set to Exq.Adapters.Queue.Mock
      Add the following to your test config
      config :exq, queue_adapter: Exq.Adapters.Queue.Mock
      """
    end

    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  def set_mode(mode) when mode in [:redis, :inline] do
    GenServer.call(__MODULE__, {:mode, self(), mode}, @timeout)
  end

  ### Private

  @impl true
  def init(options) do
    {:ok, %State{default_mode: Keyword.get(options, :mode, :redis)}}
  end

  def enqueue(pid, queue, worker, args, options) do
    {:ok, runnable} =
      GenServer.call(
        __MODULE__,
        {:enqueue, self(), :enqueue, [pid, queue, worker, args, options]},
        @timeout
      )

    runnable.()
  end

  def enqueue_at(pid, queue, time, worker, args, options) do
    {:ok, runnable} =
      GenServer.call(
        __MODULE__,
        {:enqueue, self(), :enqueue_at, [pid, queue, time, worker, args, options]},
        @timeout
      )

    runnable.()
  end

  def enqueue_in(pid, queue, offset, worker, args, options) do
    {:ok, runnable} =
      GenServer.call(
        __MODULE__,
        {:enqueue, self(), :enqueue_in, [pid, queue, offset, worker, args, options]},
        @timeout
      )

    runnable.()
  end

  @impl true
  def handle_call({:enqueue, owner_pid, type, args}, _from, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid, state.default_mode)

    runnable =
      case state.modes[owner_pid] do
        :redis ->
          fn -> apply(Redis, type, args) end

        :inline ->
          fn ->
            jid = UUID.uuid4()

            case args do
              [_pid, _queue, worker, args, _options] ->
                apply(worker, :perform, args)

              [_pid, _queue, _time_or_offset, worker, args, _options] ->
                apply(worker, :perform, args)
            end

            {:ok, jid}
          end
      end

    {:reply, {:ok, runnable}, state}
  end

  def handle_call({:mode, owner_pid, mode}, _from, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid, mode)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _, _, pid, _}, state) do
    {_, state} = pop_in(state.modes[pid])
    {:noreply, state}
  end

  defp maybe_add_and_monitor_pid(state, pid, mode) do
    case state.modes do
      %{^pid => _mode} ->
        state

      _ ->
        Process.monitor(pid)
        state = put_in(state.modes[pid], mode)
        state
    end
  end
end
