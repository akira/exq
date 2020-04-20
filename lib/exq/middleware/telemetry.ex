defmodule Exq.Middleware.Telemetry do
  @doc """
  This allows you to subscribe to the telemetry events and collect metrics about your jobs.

  ## Ecto telemetry events

  The following events are emitted:

  - `[:exq, :job, :start]`: Is invoked whenever a job starts. The measurement is a duration in seconds the job ran for.
  - `[:exq, :job, :stop]`: Is invoked whenever a job successful completes. The measurement is a duration in seconds the job ran for and a retry_count for the number of times the job has been retried.
  - `[:exq, :job, :exception]`: Is invoked whenever a job fails. The measurement is a duration in seconds the job ran for and a retry_count for the number of times the job has been retried.

  Each event has the following metadata
  - `enuqueued_at` datetime the job was enqueued
  - `queue` the name of the queue the job was executed in
  - `class` the job's class

  ### Example:
  ```
  defmodule MyApp.Application do
    def start(_type, _args) do
      children = [
        # .....
        {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
        {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end

    defp metrics do
      [
        counter("exq.job.started.count"),
        counter("exq.job.started.retry_count"),
        counter("exq.job.processed.retry_count"),
        distribution("exq.job.processed.duration",
          buckets: [0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 3, 5, 10]
        ),
        counter("exq.job.failed.retry_count"),
        distribution("exq.job.failed.duration",
          buckets: [0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 3, 5, 10]
        )
      ]
    end
  end
  ```
  """

  @behaviour Exq.Middleware.Behaviour

  import Exq.Middleware.Pipeline

  def after_failed_work(pipeline) do
    job = pipeline.assigns.job

    :telemetry.execute(
      [:exq, :job, :failed],
      %{
        duration: delta(pipeline),
        retry_count: job.retry_count || 1
      },
      tags(job)
    )

    pipeline
  end

  def after_processed_work(pipeline) do
    job = pipeline.assigns.job

    :telemetry.execute(
      [:exq, :job, :processed],
      %{
        duration: delta(pipeline),
        retry_count: job.retry_count || 0
      },
      tags(job)
    )

    pipeline
  end

  def before_work(pipeline) do
    job = pipeline.assigns.job

    :telemetry.execute(
      [:exq, :job, :started],
      %{count: 1, retry_count: job.retry_count || 0},
      tags(job)
    )

    assign(pipeline, :started_at, DateTime.utc_now())
  end

  defp tags(job),
    do: %{enqueued_at: unix_to_datetime(job.enqueued_at), queue: job.queue, class: job.class}

  defp delta(%Pipeline{assigns: assigns}),
    do: DateTime.diff(DateTime.utc_now(), assigns.started_at, :second)
end
