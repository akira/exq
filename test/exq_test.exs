Code.require_file "test_helper.exs", __DIR__


defmodule ExqTest do
  use ExUnit.Case
  use Timex
  import ExqTestUtil

  defmodule PerformWorker do
    def perform do
      send :exqtest, {:worked}
    end
  end

  defmodule PerformArgWorker do
    def perform(arg) do
      send :exqtest, {:worked, arg}
    end
  end

  defmodule SleepWorker do
    def perform(time, message) do
      :timer.sleep(time)
      send :exqtest, {message}
    end
  end

  defmodule CustomMethodWorker do
    def simple_perform do
    end
  end

  defmodule MissingMethodWorker do
  end

  defmodule FailWorker do
    def failure_perform do
      :num + 1
      send :exqtest, {:worked}
    end
  end

  setup do
    TestRedis.start
    on_exit fn ->
      wait
      TestRedis.stop
    end
    :ok
  end

  test "start using registered name" do
    {:ok, exq_sup} = Exq.start_link([port: 6555, name: :custom_manager, namespace: "test"])
    assert_exq_up(:custom_manager)
    stop_process(exq_sup)
  end

  test "start multiple exq instances using registered name" do
    {:ok, sup1} = Exq.start_link([port: 6555, name: :custom_manager1, namespace: "test"])
    assert_exq_up(:custom_manager1)

    {:ok, sup2} = Exq.start_link([port: 6555, name: :custom_manager2, namespace: "test"])
    assert_exq_up(:custom_manager2)

    stop_process(sup1)
    stop_process(sup2)
  end

  test "enqueue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test"])
    {:ok, _} = Exq.enqueue(:exq_t, "default", ExqTest.PerformWorker, [])
    wait
    assert_received {:worked}
    stop_process(sup)
  end

  test "enqueue_in and run a job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test",
                                 scheduler_enable: true, scheduler_poll_timeout: 5])
    {:ok, _} = Exq.enqueue_in(:exq_t, "default", 0, ExqTest.PerformWorker, [])
    wait_long
    assert_received {:worked}
    stop_process(sup)
  end

  test "enqueue_at and run a job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test",
                                 scheduler_enable: true, scheduler_poll_timeout: 5])
    {:ok, _} = Exq.enqueue_at(:exq_t, "default", Time.now, ExqTest.PerformWorker, [])
    wait_long
    assert_received {:worked}
    stop_process(sup)
  end

  test "enqueue with separate enqueuer" do
    Process.register(self, :exqtest)
    {:ok, exq_sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test"])
    {:ok, enq_sup} = Exq.Enqueuer.start_link([name: :exq_e, port: 6555, namespace: "test"])
    {:ok, _} = Exq.Enqueuer.enqueue(:exq_e, "default", ExqTest.PerformWorker, [])
    wait_long
    assert_received {:worked}
    stop_process(exq_sup)
    stop_process(enq_sup)
  end

  test "run jobs on multiple queues" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test", queues: ["q1", "q2"]])
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.PerformArgWorker, [2])
    wait_long
    assert_received {:worked, 1}
    assert_received {:worked, 2}
    stop_process(sup)
  end
  
  test "register queue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test", queues: ["q1"]])
    :ok = Exq.subscribe(:exq_t, "q2", 10)
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.PerformArgWorker, [2])
    
    wait_long
    assert_received {:worked, 1}
    assert_received {:worked, 2}
    stop_process(sup)
  end
  
  test "unregister queue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test", queues: ["q1","to_remove"]])
    :ok = Exq.unsubscribe(:exq_t, "to_remove")
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(:exq_t, "to_remove", ExqTest.PerformArgWorker, [2])
    wait_long
    assert_received {:worked, 1}
    refute_received {:worked, 2}
    stop_process(sup)
  end

  test "throttle workers per queue" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test", concurrency: 1, queues: ["q1", "q2"]])
    {:ok, _} = Exq.enqueue(:exq_t, "q1",ExqTest.SleepWorker, [40, :worked])
    {:ok, _} = Exq.enqueue(:exq_t, "q1",ExqTest.SleepWorker, [40, :worked2])
    {:ok, _} = Exq.enqueue(:exq_t, "q1",ExqTest.SleepWorker, [100, :finished])
    # q2 should be clear
    {:ok, _} = Exq.enqueue(:exq_t, "q2",ExqTest.SleepWorker, [100, :q2_finished])

    :timer.sleep(160)

    assert_received {"worked"}
    assert_received {"worked2"}
    refute_received {"finished"}
    assert_received {"q2_finished"}
    stop_process(sup)
  end

  test "throttle workers different concurrency per queue" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test", queues: [{"q1", 1}, {"q2", 20}]])
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.SleepWorker, [40, :worked])
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.SleepWorker, [40, :worked2])
    {:ok, _} = Exq.enqueue(:exq_t, "q1", ExqTest.SleepWorker, [100, :finished])
    # q2 should be clear
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(:exq_t, "q2", ExqTest.SleepWorker, [100, :q2_finished])

    :timer.sleep(150)

    assert_received {"worked"}
    assert_received {"worked2"}
    refute_received {"finished"}
    assert_received {"q2_finished"}
    stop_process(sup)
  end


  test "record processed jobs" do
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test"])
    state = :sys.get_state(:exq_t)

    {:ok, _} = Exq.enqueue(:exq_t, "default", "ExqTest.CustomMethodWorker/simple_perform", [])
    wait
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "1"

    {:ok, _} = Exq.enqueue(:exq_t, "default", "ExqTest.CustomMethodWorker/simple_perform", [])
    wait_long
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "2"

    stop_process(sup)
  end

  test "record failed jobs" do
    {:ok, sup} = Exq.start_link([name: :exq_t, port: 6555, namespace: "test"])
    state = :sys.get_state(:exq_t)

    {:ok, _} = Exq.enqueue(:exq_t, "default", "ExqTest.MissingMethodWorker/fail", [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "1"

    {:ok, _} = Exq.enqueue(:exq_t, "default", ExqTest.MissingWorker, [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "2"


    {:ok, jid} = Exq.enqueue(:exq_t, "default", "ExqTest.FailWorker/failure_perform", [])

    # if we kill Exq too fast we dont record the failure because exq is gone
    wait_long

    {:ok, enq_sup} = Exq.Enqueuer.Server.start_link([name: :exq_e, port: 6555, namespace: "test"])

    # Find the job in the processed queue
    {:ok, _, _} = Exq.Api.find_failed(:exq_e, jid)

    wait_long

    stop_process(sup)
    stop_process(enq_sup)
  end
end
