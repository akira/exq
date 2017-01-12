defmodule UniquenessAcceptanceTest do
  use ExUnit.Case, async: false
  import ExqTestUtil
  alias Exq.Redis.JobQueue
  alias Exq.Worker.Server, as: Worker

  @namespace "exq"
  @queue "default"
  @main_pid :mainserver
  @runner_pid :exunittest
  @redis_pid :testredis
  @stub_pid :stubserver
  @enqueuer_pid :enqueuerserver
  @manager_pid :managerserver
  @middleware_pid :"Test.Middleware.Server"
  @enqueuer_pid :"Exq.Enqueuer"

  defmodule UniqueWorker do
    def perform(arg1) do
      pid = Process.whereis :"#{arg1}"
      send(pid, [:unique_worker_did_work])
    end

    def perform(arg1, arg2) do
      pid = Process.whereis :"#{arg1}"
      send(pid, [:unique_worker_did_work, arg2])
    end
  end

  setup do
    on_exit fn ->
      ExqTestUtil.reset_config
      TestRedis.teardown
    end

    ExqTestUtil.reset_config
    TestRedis.setup
    Process.register(self, @runner_pid)

    {:ok, stub_server} = GenServer.start_link(StubServer, [])
    Process.register(stub_server, @stub_pid)

    {:ok, manager} = Exq.Manager.Server.start_link(
      name: @manager_pid, queues: [@queue], namespace: @namespace,
      concurrency: [{@queue, 1, 0}], redis: @redis_pid, redis_timeout: 1000, poll_timeout: 3000,
      workers_sup: @runner_pid
    )

    {:ok, enqueuer} = GenServer.start_link(Exq.Enqueuer.Server,
      [namespace: @namespace, redis: @redis_pid]
    )
    Process.register(enqueuer, @enqueuer_pid)

    {:ok, middleware} = Exq.Middleware.Server.start_link(name: "Test", default_middleware: [])
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Job)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Manager)
    Exq.Middleware.Server.push(middleware, Exq.Middleware.Uniqueness)

    work_table = :ets.new(:work_table, [:set, :public])
    {:ok, %{work_table: work_table}}
  end

  test "does not enqueue unique workers until they have completed", %{work_table: work_table} do
     step("The first job is queued")
     queue_new_unique_worker

     step("and there is a single job in the queue")
     assert_queued_jobs(1)

     step("then a second identical job is requested")
     queue_new_unique_worker

     step("but no additional job is added to the queue")
     assert_queued_jobs(1)

     step("when that a worker starts on the queue")
     finish_all_jobs(work_table)
     wait

     step("the worker completes successfully")
     assert_worker_completed

     step("then there are no jobs on the queue")
     assert_queued_jobs(0)

     step("the job is requested again")
     queue_new_unique_worker

     step("and it is added to the queue")
     wait_long
     assert_queued_jobs(1)
  end

  test "does not enqueue unique workers until completed when using a unique key", %{work_table: work_table} do
    assert_queued_jobs(0)

    step("The first job is queued")
    queue_new_unique_worker(key: "uniq", arg: 1)

    step("and there is a single job in the queue")
    assert_queued_jobs(1)

    step("then a second identical job is requested")
    queue_new_unique_worker(key: "uniq", arg: 1)

    step("but no additional job is added to the queue")
    assert_queued_jobs(1)

    step("then a job is requested with a different argument but the same key")
    queue_new_unique_worker(key: "uniq", arg: 2)

    step("still no additional job is added to the queue")
    assert_queued_jobs(1)

    step("when a worker starts on the queue")
    finish_all_jobs(work_table)
    wait

    step("the worker completes successfully")
    assert_worker_completed(1)

    step("then there are no jobs on the queue")
    assert_queued_jobs(0)

    step("the same job is requested again, now the original has finished")
    queue_new_unique_worker(key: "uniq", arg: 1)

    step("and it is added to the queue")
    wait_long
    assert_queued_jobs(1)

    step("a job is requested with a different key")
    queue_new_unique_worker(key: "another_uniq", arg: 1)

    step("and it is added to the queue as well")
    wait_long
    assert_queued_jobs(2)
  end

  defp step(message) do
    IO.puts "#=== STEP: #{message} ==="
  end

  defp queue_new_unique_worker do
    GenServer.call(@enqueuer_pid, {:enqueue_unique, "default", UniqueWorker, [@runner_pid]})
    wait
  end

  defp queue_new_unique_worker(key: key, arg: arg) do
    GenServer.call(@enqueuer_pid, {:enqueue_unique, "default", UniqueWorker, [@runner_pid, arg], key})
    wait
  end

  defp assert_queued_jobs(count) do
    assert count == JobQueue.queue_size(@redis_pid, @namespace, @queue)
  end

  defp assert_worker_completed do
    assert_receive [:unique_worker_did_work]
  end
  defp assert_worker_completed(arg) do
    assert_receive [:unique_worker_did_work, arg]
  end

  defp finish_job(job, work_table) do
    {:ok, worker} = Worker.start_link(
      Poison.encode!(job), @manager_pid, @queue, work_table, @stub_pid,
      @namespace, "localhost", @redis_pid, @middleware_pid
    )

    Worker.work(worker)
    job.jid
  end

  defp finish_all_jobs(work_table) do
    jobs = JobQueue.jobs(@redis_pid, @namespace, @queue)
    |> Enum.map(&(finish_job(&1, work_table)))
  end
end
