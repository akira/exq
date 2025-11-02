defmodule ApiTest do
  use ExUnit.Case
  import ExqTestUtil
  alias Exq.Redis.JobStat
  alias Exq.Redis.JobQueue
  alias Exq.Support.Process
  alias Exq.Support.Job
  alias Exq.Support.Node

  setup do
    TestRedis.setup()
    Exq.start_link()

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)

    :ok
  end

  test "queues when empty" do
    assert {:ok, []} = Exq.Api.queues(Exq.Api)
  end

  test "queues when present" do
    Exq.enqueue(Exq, ~c"custom", Bogus, [])
    assert {:ok, ["custom"]} = Exq.Api.queues(Exq.Api)
  end

  test "remove invalid queue" do
    assert :ok = Exq.Api.remove_queue(Exq.Api, "custom")
  end

  test "remove queue" do
    Exq.enqueue(Exq, "custom", Bogus, [])
    assert {:ok, ["custom"]} = Exq.Api.queues(Exq.Api)
    assert :ok = Exq.Api.remove_queue(Exq.Api, "custom")
    assert {:ok, []} = Exq.Api.queues(Exq.Api)
  end

  test "empty node list" do
    assert {:ok, []} = Exq.Api.nodes(Exq.Api)
  end

  test "nodes when present" do
    JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})
    JobStat.node_ping(:testredis, "test", %Node{identity: "host2", busy: 1})
    {:ok, nodes} = Exq.Api.nodes(Exq.Api)
    assert ["host1", "host2"] == Enum.map(nodes, & &1.identity) |> Enum.sort()
  end

  test "busy processes when empty" do
    assert {:ok, 0} = Exq.Api.busy(Exq.Api)
  end

  test "busy processes when processing" do
    Exq.enqueue(Exq, ~c"custom", Bogus, [])
    JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})
    assert {:ok, 1} = Exq.Api.busy(Exq.Api)
  end

  test "stats when empty" do
    assert {:ok, 0} = Exq.Api.stats(Exq.Api, "processed")
    assert {:ok, 0} = Exq.Api.stats(Exq.Api, "failed")
  end

  test "stats with data" do
    state = :sys.get_state(Exq)
    JobStat.record_processed(:testredis, state.namespace, %{})
    JobStat.record_failure(:testredis, state.namespace, %{}, %{})

    assert {:ok, 1} = Exq.Api.stats(Exq.Api, "failed")
    assert {:ok, 1} = Exq.Api.stats(Exq.Api, "processed")
    assert {:ok, 1} = Exq.Api.stats(Exq.Api, "processed", Date.to_string(Date.utc_today()))

    assert {:ok, [1, 0]} =
             Exq.Api.stats(Exq.Api, "failed", [
               Date.to_string(Date.utc_today()),
               Date.to_string(Date.utc_today() |> Date.add(-1))
             ])
  end

  test "processes when empty" do
    assert {:ok, []} = Exq.Api.processes(Exq.Api)
  end

  test "processes with data" do
    JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})

    JobStat.add_process(:testredis, "test", %Process{
      host: "host1",
      pid: inspect(self()),
      payload: %Job{}
    })

    assert {:ok, [processes]} = Exq.Api.processes(Exq.Api)
    my_pid_str = inspect(self())
    assert %Process{pid: ^my_pid_str} = processes
  end

  test "send signal" do
    assert [] == JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})
    assert :ok = Exq.Api.send_signal(Exq.Api, "host1", "TSTP")
    assert ["TSTP"] == JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})
    assert [] == JobStat.node_ping(:testredis, "test", %Node{identity: "host1", busy: 1})
  end

  test "jobs when empty" do
    assert {:ok, []} = Exq.Api.jobs(Exq.Api)
  end

  test "jobs when enqueued" do
    {:ok, jid1} = Exq.enqueue(Exq, ~c"custom1", Bogus, [])
    {:ok, jid2} = Exq.enqueue(Exq, ~c"custom2", Bogus, [12345])
    {:ok, jobs} = Exq.Api.jobs(Exq.Api)
    assert Enum.find(jobs, fn {queue, [job]} -> queue == "custom1" && job.jid == jid1 end)
    assert Enum.find(jobs, fn {queue, [job]} -> queue == "custom2" && job.jid == jid2 end)
  end

  test "jobs for queue when empty" do
    assert {:ok, []} = Exq.Api.jobs(Exq.Api, ~c"custom")
  end

  test "jobs for queue when enqueued" do
    {:ok, jid1} = Exq.enqueue(Exq, ~c"custom", Bogus, [])
    {:ok, jid2} = Exq.enqueue(Exq, ~c"custom", Bogus, [12345])
    {:ok, jobs} = Exq.Api.jobs(Exq.Api, ~c"custom")
    assert Enum.count(jobs) == 2
    assert Enum.find(jobs, fn job -> job.jid == jid1 end)
    assert Enum.find(jobs, fn job -> job.jid == jid2 end)

    {:ok, [job]} = Exq.Api.jobs(Exq.Api, "custom", size: 1, offset: 1)
    assert job.jid == jid1

    {:ok, [json]} = Exq.Api.jobs(Exq.Api, "custom", size: 1, raw: true)
    assert Jason.decode!(json)["jid"] == jid2
  end

  test "failed when empty" do
    assert {:ok, []} = Exq.Api.failed(Exq.Api)
  end

  test "failed with data" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1"}, "this is an error")
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "2"}, "this is an error")
    {:ok, jobs} = Exq.Api.failed(Exq.Api)
    assert Enum.count(jobs) == 2
    assert Enum.at(jobs, 0).jid == "2"

    {:ok, [json]} = Exq.Api.failed(Exq.Api, raw: true, size: 1, offset: 1)
    assert Jason.decode!(json)["jid"] == "1"
  end

  test "retry when empty" do
    assert {:ok, []} = Exq.Api.retries(Exq.Api)
  end

  defmodule ConstantBackoff do
    @behaviour Exq.Backoff.Behaviour

    def offset(_job) do
      1
    end
  end

  test "retry with data" do
    with_application_env(:exq, :backoff, ConstantBackoff, fn ->
      JobQueue.retry_job(:testredis, "test", %Job{jid: "1"}, 1, "this is an error")
      JobQueue.retry_job(:testredis, "test", %Job{jid: "2"}, 1, "this is an error")
      {:ok, jobs} = Exq.Api.retries(Exq.Api)
      assert Enum.count(jobs) == 2
      assert Enum.at(jobs, 0).jid == "1"

      {:ok, [job]} = Exq.Api.retries(Exq.Api, size: 1, raw: true, offset: 1)
      assert Jason.decode!(job)["jid"] == "2"
    end)
  end

  test "scheduled when empty" do
    assert {:ok, []} = Exq.Api.scheduled(Exq.Api)
  end

  test "scheduled with data" do
    {:ok, jid1} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    {:ok, jid2} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    {:ok, jobs} = Exq.Api.scheduled(Exq.Api)
    assert Enum.count(jobs) == 2
    assert Enum.at(jobs, 0).jid == jid1

    {:ok, [job]} = Exq.Api.scheduled(Exq.Api, size: 1, raw: true, offset: 1)
    assert Jason.decode!(job)["jid"] == jid2
  end

  test "scheduled with scores and data" do
    {:ok, jid} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    {:ok, jobs} = Exq.Api.scheduled_with_scores(Exq.Api)
    assert Enum.count(jobs) == 1
    [{job, _score}] = jobs
    assert job.jid == jid
  end

  test "find_job when missing" do
    assert {:ok, nil} = Exq.Api.find_job(Exq.Api, ~c"custom", ~c"not_here")
  end

  test "find_job with job" do
    {:ok, jid} = Exq.enqueue(Exq, ~c"custom", Bogus, [])
    assert {:ok, job} = Exq.Api.find_job(Exq.Api, ~c"custom", jid)
    assert job.jid == jid
  end

  test "find job in retry queue" do
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")
    {:ok, job} = Exq.Api.find_retry(Exq.Api, "1234")
    assert job.jid == "1234"

    {:ok, [{job, score}]} = Exq.Api.retries(Exq.Api, score: true)
    {:ok, job} = Exq.Api.find_retry(Exq.Api, score, job.jid)
    assert job.jid == "1234"
  end

  test "find job in scheduled queue" do
    {:ok, jid} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    {:ok, job} = Exq.Api.find_scheduled(Exq.Api, jid)
    assert job.jid == jid

    {:ok, [{_, score}]} = Exq.Api.scheduled(Exq.Api, score: true)
    {:ok, job} = Exq.Api.find_scheduled(Exq.Api, score, jid)
    assert job.jid == jid
  end

  test "find job in failed queue" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234"}, "this is an error")
    {:ok, job} = Exq.Api.find_failed(Exq.Api, "1234")
    assert job.jid == "1234"

    {:ok, [{_job, score}]} = Exq.Api.failed(Exq.Api, score: true)
    {:ok, job} = Exq.Api.find_failed(Exq.Api, score, "1234")
    assert job.jid == "1234"
  end

  test "remove job" do
    {:ok, jid} = Exq.enqueue(Exq, ~c"custom", Bogus, [])
    Exq.Api.remove_job(Exq.Api, ~c"custom", jid)
    assert {:ok, nil} = Exq.Api.find_job(Exq.Api, ~c"custom", jid)
  end

  test "remove enqueued jobs" do
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [])
    assert {:ok, 1} = Exq.Api.queue_size(Exq.Api, "custom")
    {:ok, [job]} = Exq.Api.jobs(Exq.Api, "custom", raw: true)
    :ok = Exq.Api.remove_enqueued_jobs(Exq.Api, "custom", [job])
    assert {:ok, 0} = Exq.Api.queue_size(Exq.Api, "custom")
  end

  test "remove enqueued jobs but keep unique tokens" do
    {:ok, jid} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, [job]} = Exq.Api.jobs(Exq.Api, "custom", raw: true)
    :ok = Exq.Api.remove_enqueued_jobs(Exq.Api, "custom", [job])

    assert {:conflict, ^jid} =
             Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "remove enqueued jobs and clear their unique tokens" do
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [])
    {:ok, [_j1, _j2] = raw_jobs} = Exq.Api.jobs(Exq.Api, "custom", raw: true)
    :ok = Exq.Api.remove_enqueued_jobs(Exq.Api, "custom", raw_jobs, clear_unique_tokens: true)
    assert {:ok, []} = Exq.Api.jobs(Exq.Api, "custom", raw: true)
    assert {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "remove job in retry queue" do
    jid = "1234"
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")
    Exq.Api.remove_retry(Exq.Api, jid)
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
  end

  test "remove jobs in retry queue" do
    jid = "1234"
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")
    {:ok, [raw_job]} = Exq.Api.retries(Exq.Api, raw: true)
    Exq.Api.remove_retry_jobs(Exq.Api, [raw_job])
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
  end

  test "remove jobs in retry queue and clear their unique tokens" do
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [])
    {:ok, [job1, job2]} = Exq.Api.jobs(Exq.Api, "custom")
    JobQueue.retry_job(:testredis, 'test', job1, 1, "this is an error")
    JobQueue.retry_job(:testredis, 'test', job2, 1, "this is an another error")
    {:ok, [_j1, _j2] = raw_jobs} = Exq.Api.retries(Exq.Api, raw: true)
    :ok = Exq.Api.remove_retry_jobs(Exq.Api, raw_jobs, clear_unique_tokens: true)
    assert {:ok, []} = Exq.Api.retries(Exq.Api, raw: true)
    assert {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "remove jobs in retry queue but keep unique tokens" do
    {:ok, jid} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, [job]} = Exq.Api.jobs(Exq.Api, "custom")
    JobQueue.retry_job(:testredis, 'test', job, 1, "this is an error")
    {:ok, [raw_job]} = Exq.Api.retries(Exq.Api, raw: true)
    :ok = Exq.Api.remove_retry_jobs(Exq.Api, [raw_job])

    assert {:conflict, ^jid} =
             Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "re enqueue jobs in retry queue" do
    jid = "1234"

    JobQueue.retry_job(
      :testredis,
      ~c"test",
      %Job{jid: "1234", queue: "test"},
      1,
      "this is an error"
    )

    {:ok, [raw_job]} = Exq.Api.retries(Exq.Api, raw: true)
    assert {:ok, 1} = Exq.Api.dequeue_retry_jobs(Exq.Api, [raw_job])
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
    assert {:ok, 0} = Exq.Api.dequeue_retry_jobs(Exq.Api, [raw_job])
    assert {:ok, [^raw_job]} = Exq.Api.jobs(Exq.Api, "test", raw: true)
  end

  test "remove job in scheduled queue" do
    {:ok, jid} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    Exq.Api.remove_scheduled(Exq.Api, jid)
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
  end

  test "remove jobs in scheduled queue" do
    {:ok, jid} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    {:ok, [raw_job]} = Exq.Api.scheduled(Exq.Api, raw: true)
    Exq.Api.remove_scheduled_jobs(Exq.Api, [raw_job])
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
  end

  test "remove scheduled jobs but keep unique tokens" do
    {:ok, jid} =
      Exq.enqueue_in(Exq, "custom", 1000, Bogus, [], unique_for: 60, unique_token: "t1")

    {:ok, [job]} = Exq.Api.scheduled(Exq.Api, raw: true)
    :ok = Exq.Api.remove_scheduled_jobs(Exq.Api, [job])
    {:ok, []} = Exq.Api.scheduled(Exq.Api, raw: true)

    assert {:conflict, ^jid} =
             Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "remove scheduled jobs and clear their unique tokens" do
    {:ok, _} = Exq.enqueue_in(Exq, "custom", 1000, Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, _} = Exq.enqueue_in(Exq, "custom", 1000, Bogus, [])
    {:ok, [_j1, _j2] = raw_jobs} = Exq.Api.scheduled(Exq.Api, raw: true)
    :ok = Exq.Api.remove_scheduled_jobs(Exq.Api, raw_jobs, clear_unique_tokens: true)
    assert {:ok, []} = Exq.Api.scheduled(Exq.Api, raw: true)
    assert {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "enqueue jobs in scheduled queue" do
    {:ok, jid} = Exq.enqueue_in(Exq, "custom", 1000, Bogus, [])
    {:ok, [raw_job]} = Exq.Api.scheduled(Exq.Api, raw: true)
    {:ok, 1} = Exq.Api.dequeue_scheduled_jobs(Exq.Api, [raw_job])
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
    {:ok, 0} = Exq.Api.dequeue_scheduled_jobs(Exq.Api, [raw_job])
    assert {:ok, [^raw_job]} = Exq.Api.jobs(Exq.Api, "custom", raw: true)
  end

  test "remove job in failed queue" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234"}, "this is an error")
    Exq.Api.remove_failed(Exq.Api, "1234")
    {:ok, nil} = Exq.Api.find_failed(Exq.Api, "1234")
  end

  test "remove jobs in failed queue" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234"}, "this is an error")
    {:ok, [raw_job]} = Exq.Api.failed(Exq.Api, raw: true)
    Exq.Api.remove_failed_jobs(Exq.Api, [raw_job])
    {:ok, nil} = Exq.Api.find_failed(Exq.Api, "1234")
  end

  test "remove jobs in failed queue and clear their unique tokens" do
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [])
    {:ok, [job1, job2]} = Exq.Api.jobs(Exq.Api, "custom")
    JobQueue.fail_job(:testredis, 'test', job1, "this is an error")
    JobQueue.fail_job(:testredis, 'test', job2, "this is an another error")
    {:ok, [_j1, _j2] = raw_jobs} = Exq.Api.failed(Exq.Api, raw: true)
    :ok = Exq.Api.remove_failed_jobs(Exq.Api, raw_jobs, clear_unique_tokens: true)
    assert {:ok, []} = Exq.Api.failed(Exq.Api, raw: true)
    assert {:ok, _} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "remove jobs in failed queue but keep unique tokens" do
    {:ok, jid} = Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
    {:ok, [job]} = Exq.Api.jobs(Exq.Api, "custom")
    JobQueue.fail_job(:testredis, 'test', job, "this is an error")
    {:ok, [raw_job]} = Exq.Api.failed(Exq.Api, raw: true)
    :ok = Exq.Api.remove_failed_jobs(Exq.Api, [raw_job])

    assert {:conflict, ^jid} =
             Exq.enqueue(Exq, "custom", Bogus, [], unique_for: 60, unique_token: "t1")
  end

  test "enqueue jobs in failed queue" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234", queue: "test"}, "this is an error")
    {:ok, [raw_job]} = Exq.Api.failed(Exq.Api, raw: true)
    {:ok, 1} = Exq.Api.dequeue_failed_jobs(Exq.Api, [raw_job])
    assert {:ok, nil} = Exq.Api.find_failed(Exq.Api, "1234")
    {:ok, 0} = Exq.Api.dequeue_failed_jobs(Exq.Api, [raw_job])
    assert {:ok, [^raw_job]} = Exq.Api.jobs(Exq.Api, "test", raw: true)
  end

  test "clear job queue" do
    {:ok, jid} = Exq.enqueue(Exq, ~c"custom", Bogus, [])
    Exq.Api.remove_queue(Exq.Api, ~c"custom")
    assert {:ok, nil} = Exq.Api.find_job(Exq.Api, ~c"custom", jid)
  end

  test "clear retry queue" do
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")
    Exq.Api.clear_retries(Exq.Api)
    assert {:ok, nil} = Exq.Api.find_retry(Exq.Api, "1234")
  end

  test "clear scheduled queue" do
    {:ok, jid} = Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    Exq.Api.clear_scheduled(Exq.Api)
    assert {:ok, nil} = Exq.Api.find_scheduled(Exq.Api, jid)
  end

  test "clear failed queue" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234"}, "this is an error")
    Exq.Api.clear_failed(Exq.Api)
    {:ok, nil} = Exq.Api.find_failed(Exq.Api, "1234")
  end

  test "queue size when empty" do
    assert {:ok, []} = Exq.Api.queue_size(Exq.Api)
  end

  test "queue size with enqueued" do
    Exq.enqueue(Exq, ~c"custom", Bogus, [])
    assert {:ok, [{"custom", 1}]} = Exq.Api.queue_size(Exq.Api)
  end

  test "queue size for queue when empty" do
    assert {:ok, 0} = Exq.Api.queue_size(Exq.Api, "default")
  end

  test "queue size for queue when enqueued" do
    Exq.enqueue(Exq, ~c"custom", Bogus, [])
    assert {:ok, 1} = Exq.Api.queue_size(Exq.Api, "custom")
  end

  test "scheduled queue size when empty" do
    assert {:ok, 0} = Exq.Api.scheduled_size(Exq.Api)
  end

  test "scheduled queue size" do
    Exq.enqueue_in(Exq, ~c"custom", 1000, Bogus, [])
    assert {:ok, 1} = Exq.Api.scheduled_size(Exq.Api)
  end

  test "retry queue size when empty" do
    assert {:ok, 0} = Exq.Api.retry_size(Exq.Api)
  end

  test "retry queue size" do
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")
    assert {:ok, 1} = Exq.Api.retry_size(Exq.Api)
  end

  test "failed size when empty" do
    assert {:ok, 0} = Exq.Api.failed_size(Exq.Api)
  end

  test "failed size" do
    JobQueue.fail_job(:testredis, ~c"test", %Job{jid: "1234"}, "this is an error")
    assert {:ok, 1} = Exq.Api.failed_size(Exq.Api)
  end

  test "realtime stats when empty" do
    assert {:ok, [], []} = Exq.Api.realtime_stats(Exq.Api)
  end

  test "realtime stats with data" do
    state = :sys.get_state(Exq)
    JobStat.record_processed(:testredis, state.namespace, %{})
    JobStat.record_failure(:testredis, state.namespace, %{}, %{})
    assert {:ok, [{_, "1"}], [{_, "1"}]} = Exq.Api.realtime_stats(Exq.Api)
  end

  test "retry job" do
    JobQueue.retry_job(:testredis, ~c"test", %Job{jid: "1234"}, 1, "this is an error")

    Exq.Api.retry_job(Exq.Api, "1234")

    assert {:ok, 0} = Exq.Api.retry_size(Exq.Api)
    assert {:ok, job} = Exq.Api.find_job(Exq.Api, nil, "1234")
    assert job.jid == "1234"
  end
end
