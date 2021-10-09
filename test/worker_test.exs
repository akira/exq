defmodule WorkerTest do
  use ExUnit.Case

  defmodule NoArgWorker do
    def perform do
    end
  end

  defmodule ThreeArgWorker do
    def perform(_, _, _) do
    end
  end

  defmodule CustomMethodWorker do
    def custom_perform do
    end
  end

  defmodule MetadataWorker do
    def perform() do
      %{class: "WorkerTest.MetadataWorker"} = Exq.worker_job()
    end
  end

  defmodule MissingMethodWorker do
  end

  defmodule RaiseWorker do
    def perform do
      raise "error"
    end
  end

  defmodule SuicideWorker do
    def perform do
      Process.exit(self(), :kill)
    end
  end

  defmodule TerminateWorker do
    def perform do
      Process.exit(self(), :normal)
    end
  end

  defmodule BadArithmaticWorker do
    def perform do
      1 / 0
    end
  end

  defmodule BadMatchWorker do
    def perform do
      1 = 0
    end
  end

  defmodule FunctionClauseWorker do
    def perform do
      hello("abc")
    end

    def hello(from) when is_pid(from) do
      IO.puts("HELLO")
    end
  end

  defmodule MockStatsServer do
    use GenServer

    def init(args) do
      {:ok, args}
    end

    def handle_cast({:add_process, _, _, _}, state) do
      send(:workertest, :add_process)
      {:noreply, state}
    end

    def handle_cast({:record_processed, _, _}, state) do
      send(:workertest, :record_processed)
      {:noreply, state}
    end

    def handle_cast({:record_failure, _, _, _}, state) do
      send(:workertest, :record_failure)
      {:noreply, state}
    end

    def handle_cast({:process_terminated, _, _}, state) do
      send(:workertest, :process_terminated)
      {:noreply, state}
    end
  end

  defmodule MockServer do
    @behaviour :gen_statem

    def start_link() do
      :gen_statem.start_link(__MODULE__, [], [])
    end

    @impl true
    def callback_mode(), do: :state_functions

    @impl true
    def init([]) do
      {:ok, :connected, []}
    end

    defp reply({pid, request_id} = _from, reply) do
      send(pid, {request_id, reply})
    end

    def connected(
          :cast,
          {:pipeline, [["ZADD" | _], ["ZREMRANGEBYSCORE" | _], ["ZREMRANGEBYRANK" | _]], from,
           _timeout},
          data
        ) do
      send(:workertest, :zadd_redis)
      reply(from, {:ok, [1, 0, 0]})
      {:keep_state, data}
    end

    # Same reply as Redix connection
    def connected(:cast, {:pipeline, [["LREM" | _]], from, _timeout}, data) do
      send(:workertest, :lrem_redis)
      reply(from, {:ok, [1]})
      {:keep_state, data}
    end

    def connected(:cast, {:job_terminated, _queue, _success}, data) do
      send(:workertest, :job_terminated)
      {:keep_state, data}
    end
  end

  def assert_terminate(worker, true) do
    Exq.Worker.Server.work(worker)
    assert_receive :add_process
    assert_receive :process_terminated
    assert_receive :job_terminated
    assert_receive :record_processed
    assert_receive :lrem_redis
  end

  def assert_terminate(worker, false) do
    Exq.Worker.Server.work(worker)
    assert_receive :add_process
    assert_receive :process_terminated
    assert_receive :job_terminated
    assert_receive :record_failure
    assert_receive :zadd_redis
    assert_receive :lrem_redis
  end

  def start_worker({class, args}) do
    Process.register(self(), :workertest)
    job = "{ \"queue\": \"default\", \"class\": \"#{class}\", \"args\": #{args} }"

    {:ok, stub_server} =
      start_supervised(%{
        id: WorkerTest.MockServer,
        start: {WorkerTest.MockServer, :start_link, []}
      })

    {:ok, mock_stats_server} =
      start_supervised(%{
        id: WorkerTest.MockStatsServer,
        start: {GenServer, :start_link, [WorkerTest.MockStatsServer, %{}]}
      })

    {:ok, middleware} =
      start_supervised(%{
        id: Exq.Middleware.Server,
        start: {GenServer, :start_link, [Exq.Middleware.Server, []]}
      })

    {:ok, metadata} =
      start_supervised(%{
        id: Exq.Worker.Metadata,
        start: {Exq.Worker.Metadata, :start_link, [%{}]}
      })

    Exq.Middleware.Server.push(middleware, Exq.Middleware.Stats)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Job)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Manager)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Logger)

    start_supervised(%{
      id: Exq.Worker.Server,
      start:
        {Exq.Worker.Server, :start_link,
         [
           job,
           stub_server,
           "default",
           mock_stats_server,
           "exq",
           "localhost",
           stub_server,
           middleware,
           metadata
         ]}
    })
  end

  test "execute valid job with perform" do
    {:ok, worker} = start_worker({"WorkerTest.NoArgWorker", "[]"})
    assert_terminate(worker, true)
  end

  test "execute valid rubyish job with perform" do
    {:ok, worker} = start_worker({"WorkerTest::NoArgWorker", "[]"})
    assert_terminate(worker, true)
  end

  test "execute valid job with perform args" do
    {:ok, worker} = start_worker({"WorkerTest.ThreeArgWorker", "[1, 2, 3]"})
    assert_terminate(worker, true)
  end

  test "provide access to job metadata" do
    {:ok, worker} = start_worker({"WorkerTest.MetadataWorker", "[]"})
    assert_terminate(worker, true)
  end

  test "execute worker raising error" do
    {:ok, worker} = start_worker({"WorkerTest.RaiseWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "execute valid job with custom function" do
    {:ok, worker} = start_worker({"WorkerTest.CustomMethodWorker/custom_perform", "[]"})
    assert_terminate(worker, false)
  end

  # Go through Exit reasons: http://erlang.org/doc/reference_manual/errors.html#exit_reasons

  test "execute invalid module perform" do
    {:ok, worker} = start_worker({"NonExistant", "[]"})
    assert_terminate(worker, false)
  end

  test "worker killed still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.SuicideWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "worker normally terminated still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.TerminateWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "worker with arithmatic error (badarith) still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.BadArithmaticWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "worker with bad match (badmatch) still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.BadMatchWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "worker with function clause error still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.FunctionClauseWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "execute invalid module function" do
    {:ok, worker} = start_worker({"WorkerTest.MissingMethodWorker/nonexist", "[]"})
    assert_terminate(worker, false)
  end

  test "adds process info struct to worker state" do
    {:ok, worker} = start_worker({"WorkerTest.NoArgWorker", "[]"})
    assert is_nil(:sys.get_state(worker).pipeline)

    Exq.Worker.Server.work(worker)
    assert is_map(:sys.get_state(worker).pipeline.assigns.process_info)
  end

  test "adds job struct to worker state" do
    {:ok, worker} = start_worker({"WorkerTest.NoArgWorker", "[]"})
    assert is_nil(:sys.get_state(worker).pipeline)

    Exq.Worker.Server.work(worker)
    assert is_map(:sys.get_state(worker).pipeline.assigns.job)
  end

  test "adds worker module to worker state" do
    {:ok, worker} = start_worker({"WorkerTest.NoArgWorker", "[]"})
    assert is_nil(:sys.get_state(worker).pipeline)

    Exq.Worker.Server.work(worker)
    assert :sys.get_state(worker).pipeline.assigns.worker_module == Elixir.WorkerTest.NoArgWorker
  end
end
