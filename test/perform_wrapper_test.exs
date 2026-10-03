defmodule PerformWrapperTest do
  use ExUnit.Case

  alias Exq.Middleware.Pipeline

  # Each test supplies its own worker and middleware callbacks.
  defmodule Worker do
    def perform(value) do
      %{test_pid: test_pid, perform: perform} = Agent.get(PerformWrapperTest.Callbacks, & &1)
      job = Exq.worker_job(PerformWrapperTest)
      send(test_pid, {:perform, self(), job, Process.get(:job_context)})
      result = perform.(value)
      send(test_pid, {:worker_returned, result})
      result
    end
  end

  defmodule OuterMiddleware do
    @behaviour Exq.Middleware.Behaviour

    def before_work(pipeline) do
      callbacks = Agent.get(PerformWrapperTest.Callbacks, & &1)

      pipeline =
        pipeline
        |> Pipeline.assign(:test_pid, callbacks.test_pid)
        |> Pipeline.assign(:test_callbacks, callbacks)
        |> callbacks.before_work.()

      send(callbacks.test_pid, {:before_work, pipeline})
      pipeline
    end

    def around_perform(pipeline, next) do
      pipeline.assigns.test_callbacks.around_perform.(pipeline, next)
    end

    def after_processed_work(pipeline) do
      send(pipeline.assigns.test_pid, {:processed, pipeline})
      pipeline
    end

    def after_failed_work(pipeline) do
      send(pipeline.assigns.test_pid, {:failed, pipeline})
      pipeline
    end
  end

  defmodule InnerMiddleware do
    @behaviour Exq.Middleware.Behaviour

    def before_work(pipeline), do: pipeline
    def after_processed_work(pipeline), do: pipeline
    def after_failed_work(pipeline), do: pipeline

    def around_perform(pipeline, next) do
      pipeline.assigns.test_callbacks.inner_perform.(pipeline, next)
    end
  end

  defmodule LifecycleOnly do
    @behaviour Exq.Middleware.Behaviour

    def before_work(pipeline) do
      send(pipeline.assigns.test_pid, {:lifecycle, :before_work, self()})
      pipeline
    end

    def after_processed_work(pipeline) do
      send(pipeline.assigns.test_pid, {:lifecycle, :after_processed_work, self()})
      pipeline
    end

    def after_failed_work(pipeline) do
      send(pipeline.assigns.test_pid, {:lifecycle, :after_failed_work, self()})
      pipeline
    end
  end

  setup do
    TestRedis.setup()

    on_exit(fn ->
      ExqTestUtil.wait()
      TestRedis.teardown()
    end)

    callbacks = %{
      test_pid: self(),
      before_work: fn pipeline -> pipeline end,
      around_perform: fn pipeline, next -> next.(pipeline) end,
      inner_perform: fn pipeline, next -> next.(pipeline) end,
      perform: fn value -> {:ok, value} end
    }

    start_supervised!(%{
      id: PerformWrapperTest.Callbacks,
      start: {Agent, :start_link, [fn -> callbacks end, [name: PerformWrapperTest.Callbacks]]}
    })

    start_supervised!(
      {Exq,
       name: __MODULE__,
       namespace: "perform_wrapper_test:#{UUID.uuid4()}",
       queues: ["default"],
       concurrency: 1,
       poll_timeout: 10}
    )

    middleware = Exq.Middleware.Server.server_name(__MODULE__)

    Enum.each(
      [OuterMiddleware, LifecycleOnly, InnerMiddleware],
      &Exq.Middleware.Server.push(middleware, &1)
    )

    :ok
  end

  describe "successful execution" do
    test "runs middleware in order inside the Task and returns their updates to the GenServer" do
      test_pid = self()
      context = make_ref()
      meta = %{"tenant_id" => "tenant-1"}

      configure(
        before_work: fn pipeline ->
          Process.put(:job_context, context)
          Pipeline.assign(pipeline, :context, context)
        end,
        around_perform: fn pipeline, next ->
          assert pipeline.event == :around_perform
          assert Exq.worker_job(PerformWrapperTest) == pipeline.assigns.job
          send(test_pid, {:step, :outer_enter, self(), Process.get(:job_context)})
          Process.put(:job_context, pipeline.assigns.context)

          try do
            {completed, result} = next.(pipeline)
            {Pipeline.assign(completed, :outer_complete, true), result}
          after
            Process.delete(:job_context)
            send(test_pid, {:step, :outer_leave, self(), Process.get(:job_context)})
          end
        end,
        inner_perform: fn pipeline, next ->
          assert Exq.worker_job(PerformWrapperTest) == pipeline.assigns.job
          send(test_pid, {:step, :inner_enter, self(), Process.get(:job_context)})
          {completed, result} = next.(pipeline)
          send(test_pid, {:step, :inner_leave, self(), Process.get(:job_context)})
          {Pipeline.assign(completed, :inner_complete, true), result}
        end,
        perform: fn value ->
          send(test_pid, {:step, :perform, self(), Process.get(:job_context)})
          {:ok, value}
        end
      )

      assert {:ok, jid} = enqueue([42], meta: meta)
      assert_receive {:before_work, %{worker_pid: worker}}
      assert_receive {:perform, task, job, ^context}
      refute task == worker
      assert job.jid == jid
      assert job.args == [42]
      assert job.meta == meta

      for {expected_step, expected_context} <- [
            {:outer_enter, nil},
            {:inner_enter, context},
            {:perform, context},
            {:inner_leave, context},
            {:outer_leave, nil}
          ] do
        assert_receive {:step, step, ^task, observed_context}
        assert step == expected_step
        assert observed_context == expected_context
      end

      assert_receive {:lifecycle, :before_work, ^worker}
      assert_receive {:lifecycle, :after_processed_work, ^worker}
      assert_receive {:processed, pipeline}
      assert pipeline.worker_pid == worker
      assert pipeline.event == :after_processed_work
      assert pipeline.assigns.result == {:ok, 42}
      assert pipeline.assigns.inner_complete
      assert pipeline.assigns.outer_complete
      refute_receive {:failed, _}
    end

    test "updated job arguments and metadata reach perform" do
      configure(
        around_perform: fn pipeline, next ->
          job = %{pipeline.assigns.job | args: [7], meta: %{"task" => true}}
          next.(Pipeline.assign(pipeline, :job, job))
        end
      )

      assert {:ok, jid} = enqueue()
      assert_receive {:perform, _, job, _}
      assert job.jid == jid
      assert job.args == [7]
      assert job.meta == %{"task" => true}
      assert_receive {:processed, pipeline}
      assert pipeline.assigns.job == job
      assert pipeline.assigns.result == {:ok, 7}
    end

    test "middleware can return a result without calling perform" do
      configure(
        around_perform: fn pipeline, _next ->
          {Pipeline.assign(pipeline, :skipped, true), {:skipped, 42}}
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:processed, pipeline}
      assert pipeline.assigns.skipped
      assert pipeline.assigns.result == {:skipped, 42}
      refute_receive {:perform, _, _, _}
      refute_receive {:failed, _}
    end

    test "worker results that look like pipeline pairs are preserved" do
      configure(perform: fn _value -> {%Pipeline{}, 42} end)

      assert {:ok, _} = enqueue()
      assert_receive {:processed, pipeline}
      assert pipeline.assigns.result == {%Pipeline{}, 42}
    end
  end

  describe "failures" do
    @tag timeout: 5_000
    test "checkpoint calls respect genserver_timeout" do
      configure(
        around_perform: fn pipeline, next ->
          worker = pipeline.worker_pid
          :ok = :sys.suspend(worker)

          try do
            next.(pipeline)
          after
            :ok = :sys.resume(worker)
          end
        end
      )

      ExqTestUtil.with_application_env(:exq, :genserver_timeout, 100, fn ->
        assert {:ok, _} = enqueue()
        assert_receive {:failed, pipeline}, 1_000

        assert {:timeout, {GenServer, :call, [worker, {:checkpoint, _}, 100]}} =
                 pipeline.assigns.error

        assert worker == pipeline.worker_pid
        refute_receive {:perform, _, _, _}
      end)
    end

    test "worker exceptions preserve their stacktrace and run middleware cleanup" do
      test_pid = self()

      configure(
        perform: fn _value -> raise "worker failure" end,
        around_perform: fn pipeline, next ->
          try do
            next.(Pipeline.assign(pipeline, :resource, :opened))
          after
            send(test_pid, :cleaned_up)
          end
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive :cleaned_up
      assert_receive {:failed, pipeline}
      assert {%RuntimeError{message: "worker failure"}, stacktrace} = pipeline.assigns.error

      assert Enum.any?(stacktrace, fn {module, function, _, _} ->
               module == Worker and function == :perform
             end)

      assert pipeline.assigns.resource == :opened
      assert pipeline.event == :after_failed_work
      refute_receive {:processed, _}
      refute_receive {:failed, _}
    end

    test "worker exits preserve their reason and run middleware cleanup" do
      test_pid = self()

      configure(
        perform: fn _value -> exit(:worker_exit) end,
        around_perform: fn pipeline, next ->
          try do
            next.(Pipeline.assign(pipeline, :resource, :opened))
          after
            send(test_pid, :cleaned_up)
          end
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive :cleaned_up
      assert_receive {:failed, pipeline}
      assert pipeline.assigns.error == :worker_exit
      assert pipeline.assigns.resource == :opened
      refute_receive {:processed, _}
    end

    test "an inner middleware exception keeps the outer middleware's forwarded changes" do
      configure(
        around_perform: fn pipeline, next ->
          next.(Pipeline.assign(pipeline, :progress, :outer_started))
        end,
        inner_perform: fn _pipeline, _next -> raise "inner middleware failure" end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      assert {%RuntimeError{message: "inner middleware failure"}, _} = pipeline.assigns.error
      assert pipeline.assigns.progress == :outer_started
      assert_receive {:lifecycle, :after_failed_work, _}
      refute_receive {:perform, _, _, _}
      refute_receive {:processed, _}
    end

    test "a failure before the first next keeps only the before_work changes" do
      configure(
        before_work: fn pipeline -> Pipeline.assign(pipeline, :setup_complete, true) end,
        around_perform: fn pipeline, _next ->
          _local = Pipeline.assign(pipeline, :task_only, true)
          raise "failure before next"
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      assert {%RuntimeError{message: "failure before next"}, _} = pipeline.assigns.error
      assert pipeline.assigns.setup_complete
      refute Map.has_key?(pipeline.assigns, :task_only)
      refute_receive {:perform, _, _, _}
    end

    test "a failure after next keeps the pipeline forwarded to worker execution" do
      configure(
        around_perform: fn pipeline, next ->
          next.(Pipeline.assign(pipeline, :progress, :forwarded))
          raise "failure after next"
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:perform, _, _, _}
      assert_receive {:failed, pipeline}
      assert {%RuntimeError{message: "failure after next"}, _} = pipeline.assigns.error
      assert pipeline.assigns.progress == :forwarded
      refute_receive {:processed, _}
    end

    test "an invalid callback return fails the Task but preserves completed inner updates" do
      configure(
        around_perform: fn pipeline, next ->
          {_completed, result} = next.(pipeline)
          result
        end,
        inner_perform: fn pipeline, next ->
          {completed, result} = next.(pipeline)
          {Pipeline.assign(completed, :inner_complete, true), result}
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      {reason, stacktrace} = pipeline.assigns.error
      assert %MatchError{term: {:ok, 42}} = Exception.normalize(:error, reason, stacktrace)
      assert pipeline.assigns.inner_complete
      refute_receive {:processed, _}
    end
  end

  describe "completed inner middleware updates" do
    test "survive an outer middleware exception" do
      configure(
        around_perform: fn pipeline, next ->
          next.(pipeline)
          raise "outer middleware failure"
        end,
        inner_perform: fn pipeline, next ->
          {completed, result} = next.(pipeline)
          {Pipeline.assign(completed, :inner_complete, true), result}
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      assert {%RuntimeError{message: "outer middleware failure"}, _} = pipeline.assigns.error
      assert pipeline.assigns.inner_complete
      refute_receive {:processed, _}
    end

    test "survive a hard kill in the outer middleware" do
      configure(
        around_perform: fn pipeline, next ->
          next.(pipeline)
          Process.exit(self(), :kill)
        end,
        inner_perform: fn pipeline, next ->
          {completed, result} = next.(pipeline)
          {Pipeline.assign(completed, :inner_complete, true), result}
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      assert pipeline.assigns.error == :killed
      assert pipeline.assigns.inner_complete
      refute_receive {:processed, _}
    end

    test "survive cancellation while the outer middleware waits" do
      test_pid = self()

      configure(
        around_perform: fn pipeline, next ->
          next.(pipeline)
          send(test_pid, :outer_waiting)
          receive do: (:finish -> :ok)
        end,
        inner_perform: fn pipeline, next ->
          {completed, result} = next.(pipeline)
          {Pipeline.assign(completed, :inner_complete, true), result}
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:before_work, %{worker_pid: worker}}
      assert_receive :outer_waiting
      Exq.Worker.Server.cancel(worker)

      assert_receive {:failed, pipeline}
      assert pipeline.assigns.error == :killed
      assert pipeline.assigns.job_canceled
      assert pipeline.assigns.inner_complete
      refute_receive {:processed, _}
    end
  end

  describe "hard kills and cancellation" do
    test "a hard kill inside perform skips Task cleanup but retains forwarded changes" do
      test_pid = self()

      configure(
        perform: fn _value -> Process.exit(self(), :kill) end,
        around_perform: fn pipeline, next ->
          try do
            next.(Pipeline.assign(pipeline, :resource, :opened))
          after
            send(test_pid, :cleaned_up)
          end
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:failed, pipeline}
      assert pipeline.assigns.error == :killed
      assert pipeline.assigns.resource == :opened
      refute pipeline.assigns[:job_canceled]
      refute_receive :cleaned_up
      refute_receive {:processed, _}
    end

    test "cancelling a running worker skips Task cleanup and marks the failure as cancelled" do
      test_pid = self()

      configure(
        perform: fn _value ->
          send(test_pid, :worker_waiting)
          receive do: (:finish -> :ok)
        end,
        around_perform: fn pipeline, next ->
          try do
            next.(Pipeline.assign(pipeline, :resource, :opened))
          after
            send(test_pid, :cleaned_up)
          end
        end
      )

      assert {:ok, _} = enqueue()
      assert_receive {:before_work, %{worker_pid: worker}}
      assert_receive :worker_waiting
      Exq.Worker.Server.cancel(worker)

      assert_receive {:failed, pipeline}
      assert pipeline.assigns.error == :killed
      assert pipeline.assigns.job_canceled
      assert pipeline.assigns.resource == :opened
      refute_receive :cleaned_up
      refute_receive {:processed, _}
    end

    test "a queued checkpoint preserves both cancellation and the incoming updates" do
      state = %Exq.Worker.Server.State{
        task_pid: self(),
        pipeline: %Pipeline{assigns: %{job_canceled: true}}
      }

      incoming = %Pipeline{assigns: %{job_canceled: false, progress: :updated}}

      assert {:reply, :ok, updated} =
               Exq.Worker.Server.handle_call({:checkpoint, incoming}, {self(), make_ref()}, state)

      assert updated.pipeline.assigns.job_canceled
      assert updated.pipeline.assigns.progress == :updated
    end
  end

  defp configure(callbacks) do
    Agent.update(PerformWrapperTest.Callbacks, &Map.merge(&1, Map.new(callbacks)))
  end

  defp enqueue(args \\ [42], options \\ []) do
    Exq.enqueue(__MODULE__, "default", Worker, args, Keyword.put(options, :max_retries, 0))
  end
end
