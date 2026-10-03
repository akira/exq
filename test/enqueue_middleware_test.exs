defmodule EnqueueMiddlewareTest do
  use ExUnit.Case

  alias Exq.Redis.JobQueue

  defmodule Outer do
    @behaviour Exq.Enqueue.Middleware

    def around_enqueue(pipeline, next) do
      send(self(), {:enter, :outer, self(), pipeline.operation, pipeline.jobs})

      jobs =
        Enum.map(pipeline.jobs, fn {job, options} ->
          {put_in(job.meta["outer"], true), options}
        end)

      try do
        next.(%{pipeline | jobs: jobs})
      after
        send(self(), {:leave, :outer})
      end
    end
  end

  defmodule Inner do
    @behaviour Exq.Enqueue.Middleware

    def around_enqueue(pipeline, next) do
      send(self(), {:enter, :inner, self(), pipeline.operation, pipeline.jobs})

      jobs =
        Enum.map(pipeline.jobs, fn {job, options} ->
          {put_in(job.meta["inner"], true), options}
        end)

      try do
        next.(%{pipeline | jobs: jobs})
      after
        send(self(), {:leave, :inner})
      end
    end
  end

  defmodule EchoWorker do
    def perform(value), do: value
  end

  defmodule PassThrough do
    @behaviour Exq.Enqueue.Middleware
    def around_enqueue(pipeline, next), do: next.(pipeline)
  end

  defmodule Middleware do
    @behaviour Exq.Enqueue.Middleware

    def around_enqueue(pipeline, next) do
      callback = Agent.get(__MODULE__, & &1)
      callback.(pipeline, next)
    end
  end

  defmodule StrictAdapter do
    @behaviour Exq.Adapters.Queue

    def enqueue(target, queue, worker, args, options) do
      record(:enqueue, target, nil, queue, worker, args, options)
    end

    def enqueue_at(target, queue, time, worker, args, options) do
      record(:enqueue_at, target, {:at, time}, queue, worker, args, options)
    end

    def enqueue_in(target, queue, offset, worker, args, options) do
      record(:enqueue_in, target, {:in, offset}, queue, worker, args, options)
    end

    def enqueue_all(target, requests) do
      send(self(), {:adapter, :enqueue_all, target, requests})
      {:ok, Enum.map(requests, fn [_, _, _, options] -> {:ok, Keyword.fetch!(options, :jid)} end)}
    end

    defp record(operation, target, schedule, queue, worker, args, options) do
      if Keyword.has_key?(options, :schedule) do
        raise ArgumentError, "unexpected adapter option :schedule"
      end

      send(self(), {:adapter, operation, target, schedule, queue, worker, args, options})
      {:ok, Keyword.fetch!(options, :jid)}
    end
  end

  setup do
    TestRedis.setup()
    previous = Application.get_env(:exq, :enqueue_middleware)
    Application.put_env(:exq, :enqueue_middleware, [Outer, Inner])
    namespace = "enqueue_middleware:#{UUID.uuid4()}"

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:exq, :enqueue_middleware)
      else
        Application.put_env(:exq, :enqueue_middleware, previous)
      end

      TestRedis.teardown()
    end)

    start_supervised!(%{
      id: Middleware,
      start: {Agent, :start_link, [fn -> &PassThrough.around_enqueue/2 end, [name: Middleware]]}
    })

    start_supervised!({Exq, name: __MODULE__, namespace: namespace, queues: []})
    {:ok, namespace: namespace}
  end

  test "empty and pass-through middleware chains enqueue equivalent jobs", %{namespace: namespace} do
    now = DateTime.utc_now()

    options = [
      max_retries: 3,
      unique_for: 60,
      unique_until: :expiry,
      meta: %{"tenant" => "1", "settings" => %{state: :ready, labels: [:billing]}}
    ]

    [without_middleware, with_middleware] =
      for middleware <- [[], [PassThrough]] do
        Application.put_env(:exq, :enqueue_middleware, middleware)

        assert Exq.enqueue(__MODULE__, "default", MyWorker, [1], options ++ [jid: "immediate"]) ==
                 {:ok, "immediate"}

        assert Exq.enqueue_at(__MODULE__, "default", now, MyWorker, [2], options ++ [jid: "at"]) ==
                 {:ok, "at"}

        assert Exq.enqueue_in(__MODULE__, "default", 0, MyWorker, [3], options ++ [jid: "in"]) ==
                 {:ok, "in"}

        assert Exq.enqueue_all(__MODULE__, [
                 ["default", MyWorker, [4], options ++ [jid: "bulk"]],
                 [
                   "default",
                   MyWorker,
                   [5],
                   options ++ [jid: "bulk-scheduled", schedule: {:in, 0}]
                 ]
               ]) == {:ok, [{:ok, "bulk"}, {:ok, "bulk-scheduled"}]}

        assert JobQueue.scheduler_dequeue(:testredis, namespace) == 3

        jobs =
          JobQueue.jobs(:testredis, namespace, "default")
          |> Enum.map(&Map.drop(Map.from_struct(&1), [:enqueued_at, :at, :unlocks_at]))
          |> Enum.sort_by(& &1.jid)

        keys = Redix.command!(:testredis, ["KEYS", "#{namespace}:*"])
        Redix.command!(:testredis, ["DEL" | keys])
        jobs
      end

    assert length(without_middleware) == 5
    assert without_middleware == with_middleware

    assert Enum.all?(without_middleware, fn job ->
             job.meta == %{
               "tenant" => "1",
               "settings" => %{"state" => "ready", "labels" => ["billing"]}
             }
           end)
  end

  test "middleware runs in the caller and wraps the complete enqueue", %{namespace: namespace} do
    caller = self()

    assert {:ok, jid} =
             Exq.enqueue(__MODULE__, "default", MyWorker, [42], meta: %{"tenant" => "1"})

    assert_receive {:enter, :outer, ^caller, :enqueue, [{prepared, options}]}
    assert options == [meta: %{"tenant" => "1"}]
    assert prepared.jid == jid
    assert prepared.class == "MyWorker"
    assert_receive {:enter, :inner, ^caller, :enqueue, [{injected, ^options}]}
    assert injected.meta["outer"]
    assert_receive {:leave, first}
    assert first == :inner
    assert_receive {:leave, second}
    assert second == :outer

    [job] = JobQueue.jobs(:testredis, namespace, "default")
    assert job.jid == jid
    assert job.args == [42]
    assert job.meta == %{"tenant" => "1", "outer" => true, "inner" => true}
  end

  test "scheduled and bulk operations go through the same chain", %{namespace: namespace} do
    now = DateTime.utc_now()
    assert {:ok, at} = Exq.enqueue_at(__MODULE__, "default", now, MyWorker, [1])
    assert {:ok, offset} = Exq.enqueue_in(__MODULE__, "default", 0, MyWorker, [2])

    assert {:ok, [{:ok, immediate}, {:ok, scheduled}]} =
             Exq.enqueue_all(__MODULE__, [
               ["default", MyWorker, [3], []],
               ["default", MyWorker, [4], [schedule: {:in, 0}]]
             ])

    assert_receive {:enter, :outer, _, :enqueue_at, [{_, at_options}]}
    assert at_options[:schedule] == {:at, now}
    assert_receive {:enter, :outer, _, :enqueue_in, [{_, in_options}]}
    assert in_options[:schedule] == {:in, 0}

    assert_receive {:enter, :outer, _, :enqueue_all,
                    [{_, immediate_options}, {_, scheduled_options}]}

    refute Keyword.has_key?(immediate_options, :schedule)
    assert scheduled_options[:schedule] == {:in, 0}
    refute_receive {:enter, :outer, _, :enqueue_all, _}
    assert JobQueue.scheduler_dequeue(:testredis, namespace) == 3
    jobs = JobQueue.jobs(:testredis, namespace, "default")
    assert Enum.sort(Enum.map(jobs, & &1.jid)) == Enum.sort([at, offset, immediate, scheduled])
    assert Enum.all?(jobs, &(&1.meta == %{"outer" => true, "inner" => true}))
  end

  test "middleware can change or clear schedules for each single-job API", %{namespace: namespace} do
    time = DateTime.add(DateTime.utc_now(), 3600)

    for schedule <- [nil, {:at, time}, {:in, 3600}],
        operation <- [:enqueue, :enqueue_at, :enqueue_in] do
      use_middleware(fn pipeline, next ->
        jobs =
          Enum.map(pipeline.jobs, fn {job, options} ->
            {job, Keyword.put(options, :schedule, schedule)}
          end)

        next.(%{pipeline | jobs: jobs})
      end)

      options = [max_retries: 2, meta: %{"tenant" => "1"}]

      {:ok, jid} =
        case operation do
          :enqueue -> Exq.enqueue(__MODULE__, "default", MyWorker, [1], options)
          :enqueue_at -> Exq.enqueue_at(__MODULE__, "default", time, MyWorker, [1], options)
          :enqueue_in -> Exq.enqueue_in(__MODULE__, "default", 3600, MyWorker, [1], options)
        end

      {queue, other} =
        if schedule == nil, do: {"default", :scheduled}, else: {:scheduled, "default"}

      assert {:ok, job} = JobQueue.find_job(:testredis, namespace, jid, queue)
      assert job.jid == jid
      assert job.args == [1]
      assert job.retry == 2
      assert job.meta == %{"tenant" => "1"}
      assert {:ok, nil} = JobQueue.find_job(:testredis, namespace, jid, other)

      if schedule == {:at, time} do
        assert job.enqueued_at == Exq.Support.Time.unix_seconds(time)
      end
    end
  end

  test "middleware can reschedule bulk jobs", %{namespace: namespace} do
    use_middleware(fn pipeline, next ->
      jobs =
        Enum.map(pipeline.jobs, fn {job, options} ->
          {job, Keyword.put(options, :schedule, {:in, 0})}
        end)

      next.(%{pipeline | jobs: jobs})
    end)

    time = DateTime.add(DateTime.utc_now(), 3600)

    assert {:ok, [{:ok, first}, {:ok, second}, {:ok, third}]} =
             Exq.enqueue_all(__MODULE__, [
               ["default", MyWorker, [1], []],
               ["default", MyWorker, [2], [schedule: {:at, time}]],
               ["default", MyWorker, [3], [schedule: {:in, 3600}]]
             ])

    for {jid, args} <- [{first, [1]}, {second, [2]}, {third, [3]}] do
      assert {:ok, job} = JobQueue.find_job(:testredis, namespace, jid, :scheduled)
      assert job.args == args
    end

    assert JobQueue.scheduler_dequeue(:testredis, namespace) == 3
  end

  test "middleware can remove bulk schedules", %{namespace: namespace} do
    use_middleware(fn pipeline, next ->
      jobs =
        Enum.map(pipeline.jobs, fn {job, options} ->
          {job, Keyword.delete(options, :schedule)}
        end)

      next.(%{pipeline | jobs: jobs})
    end)

    time = DateTime.add(DateTime.utc_now(), 3600)

    assert {:ok, [{:ok, first}, {:ok, second}, {:ok, third}]} =
             Exq.enqueue_all(__MODULE__, [
               ["default", MyWorker, [1], []],
               ["default", MyWorker, [2], [schedule: {:at, time}]],
               ["default", MyWorker, [3], [schedule: {:in, 3600}]]
             ])

    for {jid, args} <- [{first, [1]}, {second, [2]}, {third, [3]}] do
      assert {:ok, job} = JobQueue.find_job(:testredis, namespace, jid, "default")
      assert job.args == args
      assert {:ok, nil} = JobQueue.find_job(:testredis, namespace, jid, :scheduled)
    end
  end

  test "single-job adapters receive timing arguments without a schedule option" do
    ExqTestUtil.with_application_env(:exq, :queue_adapter, StrictAdapter, fn ->
      Application.put_env(:exq, :enqueue_middleware, [])
      time = DateTime.utc_now()
      options = [jid: "adapter-job", adapter_only: :kept]

      assert Exq.enqueue(:adapter_target, "default", MyWorker, [], options) ==
               {:ok, "adapter-job"}

      assert_receive {:adapter, :enqueue, :adapter_target, nil, "default", "MyWorker", [],
                      forwarded}

      assert forwarded[:adapter_only] == :kept

      assert Exq.enqueue_at(:adapter_target, "default", time, MyWorker, [], options) ==
               {:ok, "adapter-job"}

      assert_receive {:adapter, :enqueue_at, :adapter_target, {:at, ^time}, "default", "MyWorker",
                      [], forwarded}

      assert forwarded[:adapter_only] == :kept

      assert Exq.enqueue_in(:adapter_target, "default", 60, MyWorker, [], options) ==
               {:ok, "adapter-job"}

      assert_receive {:adapter, :enqueue_in, :adapter_target, {:in, 60}, "default", "MyWorker",
                      [], forwarded}

      assert forwarded[:adapter_only] == :kept

      assert Exq.enqueue_all(:adapter_target, [
               ["default", MyWorker, [], options ++ [schedule: {:in, 60}]]
             ]) == {:ok, [{:ok, "adapter-job"}]}

      assert_receive {:adapter, :enqueue_all, :adapter_target,
                      [["default", "MyWorker", [], forwarded]]}

      assert forwarded[:schedule] == {:in, 60}
      assert forwarded[:adapter_only] == :kept
    end)
  end

  test "rescheduled single-job adapters receive no internal schedule option" do
    ExqTestUtil.with_application_env(:exq, :queue_adapter, StrictAdapter, fn ->
      time = DateTime.utc_now()

      for {schedule, expected_operation, expected_schedule} <- [
            {nil, :enqueue, nil},
            {{:at, time}, :enqueue_at, {:at, time}},
            {{:in, 60}, :enqueue_in, {:in, 60}}
          ] do
        use_middleware(fn pipeline, next ->
          jobs =
            Enum.map(pipeline.jobs, fn {job, options} ->
              {job, Keyword.put(options, :schedule, schedule)}
            end)

          next.(%{pipeline | jobs: jobs})
        end)

        options = [jid: "rescheduled", adapter_only: :kept]

        assert Exq.enqueue_at(:adapter_target, "default", time, MyWorker, [], options) ==
                 {:ok, "rescheduled"}

        assert_receive {:adapter, ^expected_operation, :adapter_target, ^expected_schedule,
                        "default", "MyWorker", [], forwarded}

        assert forwarded[:adapter_only] == :kept
      end
    end)
  end

  test "middleware can reject an enqueue without writing to Redis", %{namespace: namespace} do
    use_middleware(fn _pipeline, _next -> {:error, :blocked} end)
    assert Exq.enqueue(__MODULE__, "default", MyWorker, []) == {:error, :blocked}
    assert JobQueue.jobs(:testredis, namespace, "default") == []
  end

  test "invalid middleware output rejects the entire bulk operation", %{namespace: namespace} do
    use_middleware(
      fn pipeline, next ->
        [first, {job, options}] = pipeline.jobs
        invalid = put_in(job.meta["jid"], "override")
        next.(%{pipeline | jobs: [first, {invalid, options}]})
      end,
      [Outer, Inner, Middleware]
    )

    assert_raise ArgumentError, ~s(meta cannot override job field "jid"), fn ->
      Exq.enqueue_all(__MODULE__, [["default", MyWorker, [1], []], ["default", MyWorker, [2], []]])
    end

    assert_receive {:leave, :inner}
    assert_receive {:leave, :outer}
    assert JobQueue.jobs(:testredis, namespace, "default") == []
  end

  test "bulk serialization failure leaves all queues untouched", %{namespace: namespace} do
    for invalid <- [
          ["other", MyWorker, [make_ref()], []],
          ["other", MyWorker, [], [meta: %{"value" => make_ref()}]]
        ] do
      assert_raise Protocol.UndefinedError, fn ->
        Exq.enqueue_all(__MODULE__, [["default", MyWorker, [1], []], invalid])
      end

      assert_receive {:leave, :inner}
      assert_receive {:leave, :outer}
      assert JobQueue.jobs(:testredis, namespace, "default") == []
      assert JobQueue.jobs(:testredis, namespace, "other") == []
    end
  end

  test "uniqueness and deferred return values are unchanged", %{namespace: namespace} do
    options = [unique_for: 60, unique_until: :serial, unique_token: "serial"]
    assert {:ok, jid} = Exq.enqueue(__MODULE__, "default", MyWorker, [1], options)
    assert {:conflict, ^jid} = Exq.enqueue(__MODULE__, "default", MyWorker, [2], options)

    [{:ok, {_serialized, "default"}}] =
      JobQueue.dequeue(:testredis, namespace, "host", ["default"])

    assert {:ok, 1} = JobQueue.mark_serial_started(:testredis, namespace, "serial", jid)

    assert {:ok, [{:deferred, _}]} =
             Exq.enqueue_all(__MODULE__, [["default", MyWorker, [3], options]])
  end

  test "reordering and filtering bulk jobs keeps their options attached", %{namespace: namespace} do
    use_middleware(fn pipeline, next ->
      jobs =
        pipeline.jobs
        |> Enum.reverse()
        |> Enum.reject(fn {job, _options} -> job.args == [2] end)

      next.(%{pipeline | jobs: jobs})
    end)

    now = DateTime.utc_now()

    assert Exq.enqueue_all(__MODULE__, [
             ["default", MyWorker, [1], [jid: "same", schedule: {:at, now}, max_retries: 1]],
             ["default", MyWorker, [2], [jid: "removed"]],
             ["default", MyWorker, [3], [jid: "same", max_retries: 3]]
           ]) == {:ok, [{:ok, "same"}, {:ok, "same"}]}

    [immediate] = JobQueue.jobs(:testredis, namespace, "default")
    assert immediate.args == [3]
    assert immediate.retry == 3
    assert JobQueue.scheduler_dequeue(:testredis, namespace) == 1

    jobs = JobQueue.jobs(:testredis, namespace, "default")
    assert Enum.sort(Enum.map(jobs, &{&1.args, &1.retry})) == [{[1], 1}, {[3], 3}]
  end

  test "mock jobs use normalized worker classes" do
    Exq.Mock.set_mode(:fake)

    for middleware <- [[], [PassThrough]],
        worker <- [EchoWorker, to_string(EchoWorker), "EnqueueMiddlewareTest.EchoWorker"] do
      Application.put_env(:exq, :enqueue_middleware, middleware)
      assert {:ok, jid} = Exq.enqueue(__MODULE__, "default", worker, [42])
      job = List.last(Exq.Mock.jobs())
      assert job.jid == jid
      assert job.class == "EnqueueMiddlewareTest.EchoWorker"
    end
  end

  test "mock and inline adapters also pass through enqueue middleware" do
    Exq.Mock.set_mode(:fake)
    assert {:ok, _} = Exq.enqueue(__MODULE__, "default", MyWorker, [])
    [job] = Exq.Mock.jobs()
    assert job.meta == %{"outer" => true, "inner" => true}

    Exq.Mock.set_mode(:inline)
    assert {:ok, "inline"} = Exq.enqueue(__MODULE__, "default", EchoWorker, [42], jid: "inline")
    assert_receive {:enter, :outer, _, :enqueue, [{%{args: [42]}, _}]}
    assert_receive {:enter, :inner, _, :enqueue, [{%{args: [42]}, _}]}
  end

  defp use_middleware(callback, modules \\ [Middleware]) do
    Agent.update(Middleware, fn _previous -> callback end)
    Application.put_env(:exq, :enqueue_middleware, modules)
  end
end
