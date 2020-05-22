defmodule MiddlewareTest do
  use ExUnit.Case

  alias Exq.Middleware.Server, as: Middleware
  alias Exq.Worker.Server, as: Worker
  import ExqTestUtil

  defmodule NoArgWorker do
    def perform do
    end
  end

  defmodule MissingMethodWorker do
  end

  defmodule ConstantWorker do
    def perform do
      42
    end
  end

  defmodule RaiseWorker do
    def perform do
      raise "error"
    end
  end

  defmodule EchoMiddleware do
    @behaviour Exq.Middleware.Behaviour

    import Exq.Middleware.Pipeline

    def before_work(pipeline) do
      send(:middlewaretest, :before_work)
      pipeline
    end

    def after_processed_work(pipeline) do
      send(:middlewaretest, {:after_processed_work, pipeline.assigns.result})
      pipeline
    end

    def after_failed_work(pipeline) do
      send(:middlewaretest, {:after_failed_work, pipeline.assigns.error})
      pipeline
    end
  end

  defmodule MyMiddleware do
    @behaviour Exq.Middleware.Behaviour

    import Exq.Middleware.Pipeline

    def before_work(pipeline) do
      send(:middlewaretest, :before_work)
      assign(pipeline, :process_info, 1)
    end

    def after_processed_work(pipeline) do
      send(:middlewaretest, :after_processed_work)
      pipeline
    end

    def after_failed_work(pipeline) do
      send(:middlewaretest, :after_failed_work)
      pipeline
    end
  end

  defmodule HaltedMiddleware do
    @behaviour Exq.Middleware.Behaviour

    import Exq.Middleware.Pipeline

    def before_work(pipeline) do
      send(:middlewaretest, :before_work_halted)
      halt(pipeline)
    end

    def after_processed_work(pipeline) do
      send(:middlewaretest, :after_processed_work_halted)
      halt(pipeline)
    end

    def after_failed_work(pipeline) do
      halt(pipeline)
    end
  end

  defmodule TerminatedMiddleware do
    @behaviour Exq.Middleware.Behaviour

    import Exq.Middleware.Pipeline

    def before_work(pipeline) do
      send(:middlewaretest, :before_work_terminated)
      terminate(pipeline)
    end

    def after_processed_work(pipeline) do
      send(:middlewaretest, :after_processed_work_terminated)
      terminate(pipeline)
    end

    def after_failed_work(pipeline) do
      terminate(pipeline)
    end
  end

  defmodule StubServer do
    use GenServer

    def init(args) do
      {:ok, args}
    end

    def handle_cast(_msg, state) do
      {:noreply, state}
    end

    def handle_call(_msg, _from, state) do
      {:reply, {:ok, state}, state}
    end
  end

  def start_worker({class, args, middleware}) do
    job =
      "{ \"queue\": \"default\", \"class\": \"#{class}\", \"args\": #{args}, \"jid\": \"123\" }"

    work_table = :ets.new(:work_table, [:set, :public])
    {:ok, stub_server} = GenServer.start_link(MiddlewareTest.StubServer, [])

    {:ok, metadata} = Exq.Worker.Metadata.start_link(%{})

    Worker.start_link(
      job,
      stub_server,
      "default",
      work_table,
      stub_server,
      "exq",
      "localhost",
      :testredis,
      middleware,
      metadata
    )
  end

  setup do
    TestRedis.setup()

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)

    Process.register(self(), :middlewaretest)
    {:ok, middleware} = GenServer.start_link(Middleware, [])
    {:ok, middleware: middleware}
  end

  test "calls chain for processed work", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.NoArgWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, MyMiddleware)
    Worker.work(worker)
    state = :sys.get_state(worker)

    assert state.pipeline.assigns.process_info == 1
    assert_receive :before_work
    assert_receive :after_processed_work
  end

  test "assigns result for processed work", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.ConstantWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, EchoMiddleware)
    Worker.work(worker)

    assert_receive :before_work
    assert_receive {:after_processed_work, 42}
  end

  test "calls chain for failed work", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.MissingMethodWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, MyMiddleware)
    Worker.work(worker)
    state = :sys.get_state(worker)

    assert state.pipeline.assigns.process_info == 1
    assert_receive :before_work
    assert_receive :after_failed_work
  end

  test "assigns error for failed work", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.RaiseWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, EchoMiddleware)
    Worker.work(worker)

    assert_receive :before_work
    assert_receive {:after_failed_work, {%RuntimeError{message: "error"}, _stack}}
  end

  test "halts middleware execution", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.NoArgWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, HaltedMiddleware)
    Middleware.push(middleware, MyMiddleware)

    Worker.work(worker)
    state = :sys.get_state(worker)

    refute Map.has_key?(state.pipeline.assigns, :process_info)
    assert_receive :before_work_halted
    assert_receive :after_processed_work_halted
    refute_receive :before_work
    refute_receive :after_processed_work
  end

  test "terminates middleware execution", %{middleware: middleware} do
    {:ok, worker} = start_worker({"MiddlewareTest.NoArgWorker", "[]", middleware})
    Middleware.push(middleware, Exq.Middleware.Job)
    Middleware.push(middleware, TerminatedMiddleware)
    Middleware.push(middleware, MyMiddleware)

    Worker.work(worker)
    state = :sys.get_state(worker)

    refute Map.has_key?(state.pipeline.assigns, :process_info)
    assert_receive :before_work_terminated
    refute_receive :before_work
    refute_receive :after_processed_work_terminated
  end

  test "restores default middleware after process kill" do
    {:ok, _pid} = Exq.start_link()
    chain = [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager]
    assert Middleware.all(Middleware) == chain

    pid = Process.whereis(Middleware)
    Process.exit(pid, :kill)
    wait()

    assert Middleware.all(Middleware) == chain
  end
end
