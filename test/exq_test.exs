defmodule ExqTest do
  use ExUnit.Case
  alias Exq.Redis.JobQueue
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

  defmodule SleepLastWorker do
    def perform(time, message) do
      Process.register(self, :sleep_last_worker )
      send :exqtest, {message}
      :timer.sleep(time)
    end
  end

  defmodule EmptyMethodWorker do
    def perform do
    end
  end

  defmodule MissingMethodWorker do
  end

  defmodule FailWorker do
    def failure_perform do
      _ = :num + 1
      send :exqtest, {:worked}
    end
  end

  setup do
    TestRedis.setup
    on_exit fn ->
      wait
      TestRedis.teardown
    end
    :ok
  end

  test "start using registered name" do
    {:ok, exq_sup} = Exq.start_link(name: CustomManager)
    assert_exq_up(CustomManager)
    stop_process(exq_sup)
  end

  test "start multiple exq instances using registered name" do
    {:ok, sup1} = Exq.start_link(name: CustomManager1)
    assert_exq_up(CustomManager1)
    {:ok, sup2} = Exq.start_link(name: CustomManager2)
    assert_exq_up(CustomManager2)

    stop_process(sup1)
    stop_process(sup2)
  end

  test "enqueue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link
    {:ok, _} = Exq.enqueue(Exq, "default", ExqTest.PerformWorker, [])
    assert_receive {:worked}
    stop_process(sup)
  end

  test "run jobs from backup queue on boot" do
    host = elem(:inet.gethostname(), 1)
    Process.register(self, :exqtest)

    # enqueue and dequeue - this should now be in backup queue
    JobQueue.enqueue(:testredis, "test", "queue", ExqTest.PerformWorker, [], [])
    JobQueue.dequeue(:testredis, "test", host, ["queue"])

    # make sure jobs were requeued from backup queue
    {:ok, sup} = Exq.start_link(queues: ["default", "queue"])
    wait_long
    assert_received {:worked}

    # make sure backup queue was cleared properly if job finished
    JobQueue.re_enqueue_backup(:testredis, "test", host, "queue")
    wait_long
    refute_received {:worked}

    stop_process(sup)
  end

  test "enqueue_in and run a job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(scheduler_enable: true)
    {:ok, _} = Exq.enqueue_in(Exq, "default", 0, ExqTest.PerformWorker, [])
    assert_receive {:worked}
    stop_process(sup)
  end

  test "enqueue_at and run a job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(scheduler_enable: true)
    {:ok, _} = Exq.enqueue_at(Exq, "default", DateTime.utc_now, ExqTest.PerformWorker, [])
    assert_receive {:worked}
    stop_process(sup)
  end

  test "enqueue with separate enqueuer" do
    Process.register(self, :exqtest)
    {:ok, exq_sup} = Exq.start_link
    {:ok, enq_sup} = Exq.start_link(mode: :enqueuer, name: ExqE)
    {:ok, _} = Exq.Enqueuer.enqueue(ExqE.Enqueuer, "default", ExqTest.PerformWorker, [])
    assert_receive {:worked}
    stop_process(exq_sup)
    stop_process(enq_sup)
  end

  test "enqueue with separate enqueuer even if main Exq process is down" do
    Process.register(self, :exqtest)
    {:ok, exq_sup} = Exq.start_link
    stop_process(exq_sup)
    {:ok, enq_sup} = Exq.start_link(mode: :enqueuer)
    {:ok, _} = Exq.Enqueuer.enqueue(Exq.Enqueuer, "default", ExqTest.PerformWorker, [])

    stop_process(enq_sup)
    {:ok, exq_sup} = Exq.start_link
    assert_receive {:worked}
    stop_process(exq_sup)
  end

  test "run jobs on multiple queues" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(queues: ["q1", "q2"])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.PerformArgWorker, [2])
    assert_receive {:worked, 1}
    assert_receive {:worked, 2}
    stop_process(sup)
  end

  test "register queue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(queues: ["q1"])
    :ok = Exq.subscribe(Exq, "q2", 10)
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.PerformArgWorker, [2])

    assert_receive {:worked, 1}
    assert_receive {:worked, 2}
    stop_process(sup)
  end

  test "unregister queue and run job" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(queues: ["q1", "to_remove"])
    :ok = Exq.unsubscribe(Exq, "to_remove")
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.PerformArgWorker, [1])
    {:ok, _} = Exq.enqueue(Exq, "to_remove", ExqTest.PerformArgWorker, [2])
    assert_receive {:worked, 1}
    refute_receive {:worked, 2}
    stop_process(sup)
  end

  test "throttle workers per queue" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(concurrency: 1, queues: ["q1", "q2"])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [40, :worked])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [40, :worked2])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [100, :finished])
    # q2 should be clear
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.SleepWorker, [100, :q2_finished])

    #Timing specific - we want to ensure only x amount of jobs got done
    :timer.sleep(160)

    assert_received {"worked"}
    assert_received {"worked2"}
    refute_received {"finished"}
    assert_received {"q2_finished"}
    stop_process(sup)
  end

  test "throttle workers different concurrency per queue" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(queues: [{"q1", 1}, {"q2", 20}])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [40, :worked])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [40, :worked2])
    {:ok, _} = Exq.enqueue(Exq, "q1", ExqTest.SleepWorker, [100, :should_not_finish])
    # q2 should be clear
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.SleepWorker, [100, :q2_work])
    {:ok, _} = Exq.enqueue(Exq, "q2", ExqTest.SleepWorker, [100, :q2_finished])

    :timer.sleep(150)

    assert_received {"worked"}
    assert_received {"worked2"}
    refute_received {"should_not_finish"}
    assert_received {"q2_finished"}
    stop_process(sup)
  end

  test "record processes" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link(name: ExqP)
    state = :sys.get_state(ExqP)

    {:ok, _} = Exq.enqueue(ExqP, "default", ExqTest.SleepWorker, [100, "finished"])
    wait_long

    # Check that process has been recorded
    processes = Exq.Redis.JobStat.processes(state.redis, "test")
    assert Enum.count(processes) == 1

    wait_long
    assert_received {"finished"}

    # Check that process has been cleared
    processes = Exq.Redis.JobStat.processes(state.redis, "test")
    assert Enum.count(processes) == 0

    {:ok, _} = Exq.enqueue(ExqP, "default", ExqTest.InvalidWorker, [100, "finished"])
    wait_long

    # Check that process has been recorded
    processes = Exq.Redis.JobStat.processes(state.redis, "test")
    assert Enum.count(processes) == 0

    stop_process(sup)
  end

  test "record processed jobs" do
    {:ok, sup} = Exq.start_link(name: ExqP)
    state = :sys.get_state(ExqP)

    {:ok, _} = Exq.enqueue(ExqP, "default", ExqTest.EmptyMethodWorker, [])
    wait_long
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "1"

    {:ok, _} = Exq.enqueue(ExqP, "default", ExqTest.EmptyMethodWorker, [])
    wait_long
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "2"

    stop_process(sup)
  end

  test "record failed jobs" do
    {:ok, sup} = Exq.start_link
    state = :sys.get_state(Exq)
    {:ok, _} = Exq.enqueue(Exq, "default", "ExqTest.MissingMethodWorker/fail", [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "1"

    {:ok, _} = Exq.enqueue(Exq, "default", ExqTest.MissingWorker, [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "2"


    {:ok, jid} = Exq.enqueue(Exq, "default", "ExqTest.FailWorker/failure_perform", [])

    # if we kill Exq too fast we dont record the failure because exq is gone
    wait_long
    stop_process(sup)

    {:ok, sup} = Exq.start_link(mode: :api)

    # Find the job in the processed queue
    {:ok, _} = Exq.Api.find_failed(Exq.Api, jid)

    wait_long
    stop_process(sup)
  end

  test "configure worker shutdown time" do
    Process.register(self, :exqtest)
    {:ok, sup} = Exq.start_link([shutdown_timeout: 200])
    {:ok, _} = Exq.enqueue(Exq, "default", ExqTest.SleepWorker, [500, :long])
    {:ok, _} = Exq.enqueue(Exq, "default", ExqTest.SleepWorker, [100, :short])

    wait
    stop_process(sup)

    refute_received {"long"}
    assert_received {"short"}
  end

  test "handle supervisor tree shutdown properly with stats cleanup" do
    Process.register(self, :exqtest)

    {:ok, sup} = Exq.start_link

    # call worker that sends message and sleeps for a bit
    {:ok, _jid} = Exq.enqueue(Exq, "default", ExqTest.SleepLastWorker, [300, "worked"])

    # wait until worker started
    assert_receive {"worked"}, 100
    stop_process(sup)

    # Make sure everything is shut down properly
    assert Process.alive?(sup) == false
    assert Process.whereis(Exq.Manager.Server) == nil
    assert Process.whereis(Exq.Stats.Server) == nil
    assert Process.whereis(Exq.Scheduler.Server) == nil
    assert Process.whereis(:sleep_last_worker) == nil

    # Check that stats were cleaned up
    {:ok, sup} = Exq.start_link
    assert {:ok, []} == Exq.Api.processes(Exq.Api)

    stop_process(sup)
  end

end
