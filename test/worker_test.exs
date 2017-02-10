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

  defmodule MockStatsServer do
    use GenServer

    def handle_cast({:add_process, _, _, _}, state) do
      send :workertest, :add_process
      {:noreply, state}
    end

    def handle_cast({:record_processed, _, _}, state) do
      send :workertest, :record_processed
      {:noreply, state}
    end

    def handle_cast({:record_failure, _, _, _}, state) do
      send :workertest, :record_failure
      {:noreply, state}
    end

    def handle_cast({:process_terminated, _, _, _}, state) do
      send :workertest, :process_terminated
      {:noreply, state}
    end
  end

  defmodule MockServer do
    use GenServer

    def handle_call({:commands, [["ZADD"|_]]}, _from, state) do
      send :workertest, :zadd_redis
      {:reply, {:ok, state}, state}
    end

    def handle_call({:commands, [["LREM"|_]]}, _from, state) do
      send :workertest, :lrem_redis
      {:reply, {:ok, {}}, state}
    end

    def handle_cast({:job_terminated, _, _, _}, state) do
      send :workertest, :job_terminated
      {:noreply, state}
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

    work_table = :ets.new(:work_table, [:set, :public])
    {:ok, stub_server} = GenServer.start_link(WorkerTest.MockServer, %{})
    {:ok, mock_stats_server} = GenServer.start_link(WorkerTest.MockStatsServer, %{})
    {:ok, middleware} = GenServer.start_link(Exq.Middleware.Server, [])
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Stats)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Job)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Manager)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Logger)

    Exq.Worker.Server.start_link(job, stub_server, "default", work_table, mock_stats_server,
      "exq", "localhost", stub_server, middleware)
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

  test "execute worker raising error" do
    {:ok, worker} = start_worker({"WorkerTest.RaiseWorker", "[]"})
    assert_terminate(worker, false)
  end

  test "execute valid job with custom function" do
    {:ok, worker} = start_worker({"WorkerTest.CustomMethodWorker/custom_perform", "[]"})
    assert_terminate(worker, false)
  end

  test "execute invalid module perform" do
    {:ok, worker} = start_worker({"NonExistant", "[]"})
    assert_terminate(worker, false)
  end

  test "worker killed still sends stats" do
    {:ok, worker} = start_worker({"WorkerTest.SuicideWorker", "[]"})
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
