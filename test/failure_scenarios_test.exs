defmodule FailureScenariosTest do
  use ExUnit.Case, async: false
  import ExqTestUtil

  @moduletag :failure_scenarios

  defmodule PerformWorker do
    def perform do
      send(:exqtest, {:worked})
    end
  end

  defmodule SleepWorker do
    def perform do
      send(:exqtest, {:worked})
      Process.register(self(), :sleep_worker)
      :timer.sleep(:infinity)
    end
  end

  setup do
    TestRedis.setup()
    Application.start(:ranch)

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)

    :ok
  end

  test "handle Redis connection lost on manager" do
    conn = FlakyConnection.start(String.to_charlist(redis_host()), redis_port())

    {:ok, _} = Exq.start_link(port: conn.port)

    wait_long()
    # Stop Redis and wait for a bit
    FlakyConnection.stop(conn)
    # Not ideal - but seems to be min time for manager to die past supervision
    :timer.sleep(5100)

    # Restart Flakey connection manually, things should be back to normal
    {:ok, agent} = Agent.start_link(fn -> [] end)

    {:ok, _} =
      :ranch.start_listener(
        conn.ref,
        100,
        :ranch_tcp,
        [port: conn.port],
        FlakyConnectionHandler,
        ['127.0.0.1', redis_port(), agent]
      )

    :timer.sleep(2000)

    assert_exq_up(Exq)
    Exq.stop(Exq)
  end

  test "handle Redis connection lost on enqueue" do
    conn = FlakyConnection.start(String.to_charlist(redis_host()), redis_port())

    # Start Exq but don't listen to any queues
    {:ok, _} = Exq.start_link(port: conn.port)

    wait_long()
    # Stop Redis
    FlakyConnection.stop(conn)
    wait_long()

    # enqueue with redis stopped
    enq_result = Exq.enqueue(Exq, "default", "FakeWorker", [])
    assert enq_result == {:error, %Redix.ConnectionError{reason: :closed}}

    enq_result = Exq.enqueue_at(Exq, "default", DateTime.utc_now(), ExqTest.PerformWorker, [])
    assert enq_result == {:error, %Redix.ConnectionError{reason: :closed}}

    # Starting Redis again and things should be back to normal
    wait_long()

    # Restart Flakey connection manually
    {:ok, agent} = Agent.start_link(fn -> [] end)

    {:ok, _} =
      :ranch.start_listener(
        conn.ref,
        100,
        :ranch_tcp,
        [port: conn.port],
        FlakyConnectionHandler,
        ['127.0.0.1', redis_port(), agent]
      )

    :timer.sleep(2000)

    assert_exq_up(Exq)
    Exq.stop(Exq)
  end

  test "handle supervisor tree shutdown properly" do
    {:ok, sup} = Exq.start_link()

    assert Process.alive?(sup) == true

    # Create worker that sleeps infinitely with registered process
    {:ok, _jid} = Exq.enqueue(Exq, "default", FailureScenariosTest.SleepWorker, [])

    Process.register(self(), :exqtest)

    # wait until worker started
    assert_receive {:worked}, 500

    stop_process(sup)

    # Takes 5500 for worker to stop
    :timer.sleep(5500)

    # Make sure everything is shut down properly
    assert Process.alive?(sup) == false
    assert Process.whereis(Exq.Manager.Server) == nil
    assert Process.whereis(Exq.Stats.Server) == nil
    assert Process.whereis(Exq.Scheduler.Server) == nil
    assert Process.whereis(:sleep_worker) == nil
  end
end
