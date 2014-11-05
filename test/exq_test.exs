Code.require_file "test_helper.exs", __DIR__


defmodule ExqTest do
  use ExUnit.Case
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

  test "start using start_link" do
    {:ok, exq} = Exq.start_link([port: 6555 ])
    assert_exq_up(exq)
    Exq.stop(exq)
  end

  test "start using start" do
    {:ok, exq} = Exq.start([port: 6555 ])
    assert_exq_up(exq)
    Exq.stop(exq)
  end

  test "start using registered name" do
    {:ok, exq} = Exq.start_link([port: 6555, name: :custom_manager])
    assert_exq_up(:custom_manager)
    Exq.stop(exq)
  end

  test "start separate exq servers using registered name" do
    {:ok, exq1} = Exq.start_link([port: 6555, name: :custom_manager1])
    assert_exq_up(:custom_manager1)

    {:ok, exq2} = Exq.start_link([port: 6555, name: :custom_manager2])
    assert_exq_up(:custom_manager2)

    Exq.stop(exq1)
    Exq.stop(exq2)
  end

  test "enqueue with pid" do
    {:ok, exq} = Exq.start_link([port: 6555 ])
    {:ok, _} = Exq.enqueue(exq, "default", "MyJob", [1, 2, 3])
    Exq.stop(exq)
  end

  test "run job" do
    Process.register(self, :exqtest)
    {:ok, exq} = Exq.start_link([port: 6555, poll_timeout: 1 ])
    {:ok, _} = Exq.enqueue(exq, "default", "ExqTest.PerformWorker", [])
    wait
    assert_received {:worked}
    Exq.stop(exq)
  end

  test "run jobs on multiple queues" do
    Process.register(self, :exqtest)
    {:ok, exq} = Exq.start_link([port: 6555, queues: ["q1", "q2"], poll_timeout: 1])
    {:ok, _} = Exq.enqueue(exq, "q1", "ExqTest.PerformArgWorker", [1])
    {:ok, _} = Exq.enqueue(exq, "q2", "ExqTest.PerformArgWorker", [2])
    wait
    assert_received {:worked, 1}
    assert_received {:worked, 2}
    Exq.stop(exq)
  end

  test "record processed jobs" do
    {:ok, exq} = Exq.start_link([port: 6555, namespace: "test", poll_timeout: 1])
    state = :sys.get_state(exq)

    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTest.CustomMethodWorker/simple_perform", [])
    wait
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "1"

    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTest.CustomMethodWorker/simple_perform", [])
    wait_long
    {:ok, count} = TestStats.processed_count(state.redis, "test")
    assert count == "2"

    wait
    Exq.stop(exq)
  end

  test "record failed jobs" do
    {:ok, exq} = Exq.start_link([port: 6555, namespace: "test"])
    state = :sys.get_state(exq)

    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTest.MissingMethodWorker/fail", [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "1"

    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTest.MissingWorker", [])
    wait_long
    {:ok, count} = TestStats.failed_count(state.redis, "test")
    assert count == "2"


    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTest.FailWorker/failure_perform", [])

    # if we kill Exq too fast we dont record the failure because exq is gone
    wait_long

    # Find the job in the processed queue
    {:ok, job, idx} = Exq.find_failed(exq, jid)
    Exq.stop(exq)
  end
end
