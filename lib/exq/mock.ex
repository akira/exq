defmodule Exq.Mock do
  alias Exq.Support.Config
  alias Exq.Adapters.Queue.Redis
  alias Exq.Support.Job
  use GenServer
  @timeout 30000

  defmodule State do
    @moduledoc false
    defstruct default_mode: :redis, jobs: %{}, modes: %{}
  end

  ### Public api

  @doc """
  Start Mock server

  * `mode` - The default mode that's used for all tests. See `set_mode/1` for details.
  """
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

  @doc """
  Set the mode for current test

  * `:redis` - jobs get enqueued and processed via redis.
  * `:fake` - jobs get enqueued in a local queue
  * `:inline` - jobs get executed in the same process
  """
  def set_mode(mode) when mode in [:redis, :inline, :fake] do
    GenServer.call(__MODULE__, {:mode, self(), mode}, @timeout)
  end

  @doc """
  List of enqueued jobs

  This only works if the mode is set to `:fake`
  """
  def jobs do
    GenServer.call(__MODULE__, {:jobs, self()}, @timeout)
  end

  ### Private

  @impl true
  def init(options) do
    {:ok, %State{default_mode: Keyword.get(options, :mode, :redis)}}
  end

  @doc false
  def enqueue(pid, queue, worker, args, options) do
    {:ok, runnable} =
      GenServer.call(
        __MODULE__,
        {:enqueue, self(), :enqueue, [pid, queue, worker, args, options]},
        @timeout
      )

    runnable.()
  end

  @doc false
  def enqueue_at(pid, queue, time, worker, args, options) do
    {:ok, runnable} =
      GenServer.call(
        __MODULE__,
        {:enqueue, self(), :enqueue_at, [pid, queue, time, worker, args, options]},
        @timeout
      )

    runnable.()
  end

  @doc false
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

    case state.modes[owner_pid] do
      :redis ->
        runnable = fn -> apply(Redis, type, args) end
        {:reply, {:ok, runnable}, state}

      :inline ->
        runnable = fn ->
          job = to_job(args)
          apply(job.class, :perform, job.args)
          {:ok, job.jid}
        end

        {:reply, {:ok, runnable}, state}

      :fake ->
        job = to_job(args)
        state = update_in(state.jobs[owner_pid], &((&1 || []) ++ [job]))

        runnable = fn ->
          {:ok, job.jid}
        end

        {:reply, {:ok, runnable}, state}
    end
  end

  def handle_call({:mode, owner_pid, mode}, _from, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid, mode)
    {:reply, :ok, state}
  end

  def handle_call({:jobs, owner_pid}, _from, state) do
    jobs = state.jobs[owner_pid] || []
    {:reply, jobs, state}
  end

  @impl true
  def handle_info({:DOWN, _, _, pid, _}, state) do
    {_, state} = pop_in(state.modes[pid])
    {_, state} = pop_in(state.jobs[pid])
    {:noreply, state}
  end

  defp to_job([_pid, queue, worker, args, options]) do
    %Job{
      jid: Keyword.get_lazy(options, :jid, fn -> UUID.uuid4() end),
      queue: queue,
      class: worker,
      args: args,
      enqueued_at: DateTime.utc_now()
    }
  end

  defp to_job([_pid, queue, _time_or_offset, worker, args, options]) do
    %Job{
      jid: Keyword.get_lazy(options, :jid, fn -> UUID.uuid4() end),
      queue: queue,
      class: worker,
      args: args,
      enqueued_at: DateTime.utc_now()
    }
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
