Code.require_file "test_helper.exs", __DIR__

defmodule FailureScenariosTest do
  use ExUnit.Case
  use Timex
  import ExqTestUtil

  defmodule PerformWorker do
    def perform do
      send :exqtest, {:worked}
    end
  end

  setup do
    TestRedis.start
    on_exit fn ->
      wait
      TestRedis.teardown
    end
    :ok
  end

  test "handle Redis connection lost on manager" do
    {:ok, _} = Exq.start_link([name: :exq_f, port: 6555 ])

    # Stop Redis and wait for a bit
    TestRedis.stop
    # Not ideal - but seems to be min time for manager to die past supervision
    :timer.sleep(5000)

    # Starting Redis again, things should be back to normal
    TestRedis.start
    wait_long
    assert_exq_up(:exq_f)
    Exq.stop(:exq_f)
  end

  test "handle Redis connection lost on enqueue" do
    # Start Exq but don't listen to any queues
    {:ok, _} = Exq.start_link([name: :exq_f, port: 6555])

    # Stop Redis
    TestRedis.stop
    wait_long

    # enqueue with redis stopped
    enq_result = Exq.enqueue(:exq_f, "default", "FakeWorker", [])
    assert enq_result ==  {:error, :no_connection}

    enq_result = Exq.enqueue_at(:exq_f, "default", Time.now, ExqTest.PerformWorker, [])
    assert enq_result ==  {:error, :no_connection}

    # Starting Redis again and things should be back to normal
    wait_long
    TestRedis.start
    wait_long

    assert_exq_up(:exq_f)
    Exq.stop(:exq_f)
  end
end