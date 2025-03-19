defmodule Exq.Middleware.Telemetry do
  @moduledoc """
  This middleware allows you to subscribe to the telemetry events and
  collect metrics about your jobs.

  ### Exq telemetry events

  The middleware emits three events, same as what `:telemetry.span/3` emits.
  * `[:exq, :job, :start]` - Is invoked whenever a job starts.

      ** Measurements **

      - `system_time` (integer) - System time when the job started

  * `[:exq, :job, :stop]` - Is invoked whenever a job completes successfully.

      ** Measurements **

      - `duration` (integer) - Duration of the job execution in native unit

  * `[:exq, :job, :exception]` - Is invoked whenever a job fails.

      ** Measurements **

      - `duration` (integer) - Duration of the job execution in native unit

      ** Metadata **

      In addition to the common metadata, exception event will have the following fields.

      - `kind` (exit | error) - either `exit` or `error`
      - `reason` (term) - could be an `Exception.t/0` or term
      - `stacktrace` (list) - Stacktrace of the error. Will be empty if the kind is `exit`.

  ** Metadata **

  Each event has the following common metadata:
  * `enqueued_at` (`DateTime.t/0`) - datetime the job was enqueued
  * `queue` (`String.t/0`) - the name of the queue the job was executed in
  * `class` (`String.t/0`) - the job's class
  * `jid` (`String.t/0`) - the job's jid
  * `retry_count` (integer) - number of times this job has failed so far


  ### Examples

      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [
            # .....
            {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end

        defp metrics do
          [
            counter("exq.job.stop.duration"),
            counter("exq.job.exception.duration"),
            distribution("exq.job.stop.duration",
              buckets: [0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 3, 5, 10],
              unit: {:native, :millisecond}
            ),
            distribution("exq.job.exception.duration",
              buckets: [0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 3, 5, 10],
              unit: {:native, :millisecond}
            ),
            summary("exq.job.stop.duration", unit: {:native, :millisecond}),
            summary("exq.job.exception.duration", unit: {:native, :millisecond})
          ]
        end
      end

  """

  @behaviour Exq.Middleware.Behaviour
  alias Exq.Middleware.Pipeline
  import Pipeline

  defguardp is_stacktrace(stacktrace)
            when is_list(stacktrace) and length(stacktrace) > 0 and is_tuple(hd(stacktrace)) and
                   (tuple_size(hd(stacktrace)) == 3 or tuple_size(hd(stacktrace)) == 4)

  @impl true
  def after_failed_work(pipeline) do
    duration = System.monotonic_time() - pipeline.assigns.telemetry_start_time

    error_map =
      case pipeline.assigns.error do
        {reason, stacktrace} when is_stacktrace(stacktrace) ->
          %{kind: :error, reason: reason, stacktrace: stacktrace}

        reason ->
          %{kind: :exit, reason: reason, stacktrace: []}
      end

    :telemetry.execute(
      [:exq, :job, :exception],
      %{duration: duration},
      Map.merge(metadata(pipeline.assigns.job), error_map)
    )

    pipeline
  end

  @impl true
  def after_processed_work(pipeline) do
    duration = System.monotonic_time() - pipeline.assigns.telemetry_start_time

    :telemetry.execute(
      [:exq, :job, :stop],
      %{duration: duration},
      metadata(pipeline.assigns.job)
    )

    pipeline
  end

  @impl true
  def before_work(pipeline) do
    :telemetry.execute(
      [:exq, :job, :start],
      %{system_time: System.system_time()},
      metadata(pipeline.assigns.job)
    )

    assign(pipeline, :telemetry_start_time, System.monotonic_time())
  end

  defp metadata(job),
    do: %{
      enqueued_at: DateTime.from_unix!(round(job.enqueued_at * 1000), :millisecond),
      queue: job.queue,
      class: job.class,
      jid: job.jid,
      retry_count: job.retry_count || 0
    }
end
