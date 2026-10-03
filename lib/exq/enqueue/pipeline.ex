defmodule Exq.Enqueue.Pipeline do
  @moduledoc """
  Enqueue request passed to `Exq.Enqueue.Middleware`.

  * `jobs` contains prepared `{job, options}` pairs. Worker classes are normalized strings.
  * `operation` is `:enqueue`, `:enqueue_at`, `:enqueue_in`, or `:enqueue_all`.
  * `target` is the manager or enqueuer receiving the request.

  Each pair's `options[:schedule]` is `{:at, datetime}`, `{:in, seconds}`, or `nil`
  for immediate jobs.
  """

  alias Exq.Redis.JobQueue
  alias Exq.Support.{Config, Job, Time}

  defstruct [:operation, :target, jobs: []]

  @type t :: %__MODULE__{
          operation: :enqueue | :enqueue_at | :enqueue_in | :enqueue_all,
          target: Exq.Adapters.Queue.server(),
          jobs: [{Job.t(), keyword()}]
        }

  @doc false
  def run(target, operation, requests, schedule \\ nil) do
    validate_requests!(requests)

    target
    |> new(operation, requests, schedule)
    |> chain(Config.get(:enqueue_middleware) || [])
  end

  defp new(target, operation, requests, schedule) do
    jobs =
      Enum.map(requests, fn [queue, worker, args, options] ->
        options = normalize_options(options, operation, schedule)
        time = scheduled_at(options[:schedule])
        job = struct!(Job, JobQueue.to_job(queue, worker, args, options, time))
        {job, options}
      end)

    %__MODULE__{
      operation: operation,
      target: target,
      jobs: jobs
    }
  end

  defp normalize_options(options, :enqueue_all, _schedule), do: options
  defp normalize_options(options, _operation, nil), do: Keyword.delete(options, :schedule)

  defp normalize_options(options, _operation, schedule) do
    Keyword.put(options, :schedule, schedule)
  end

  defp scheduled_at(schedule) do
    case schedule do
      {:at, time} -> Time.unix_seconds(time)
      {:in, offset} -> Time.unix_seconds(Time.offset_from_now(offset))
      _ -> Time.unix_seconds()
    end
  end

  defp chain(pipeline, []) do
    requests =
      Enum.map(pipeline.jobs, fn {job, options} ->
        options =
          Keyword.merge(options,
            jid: job.jid,
            meta: job.meta,
            max_retries: job.retry,
            unique_for: job.unique_for,
            unique_until: job.unique_until
          )

        options =
          if job.unique_token do
            Keyword.put(options, :unique_token, job.unique_token)
          else
            options
          end

        [job.queue, job.class, job.args, options]
      end)

    validate_requests!(requests)
    dispatch(pipeline.target, pipeline.operation, requests)
  end

  defp chain(pipeline, [middleware | rest]) do
    middleware.around_enqueue(pipeline, fn updated -> chain(updated, rest) end)
  end

  defp validate_requests!(requests) do
    Enum.each(requests, fn [_queue, _worker, _args, options] ->
      Job.validate_meta!(Keyword.get(options, :meta, %{}))
    end)
  end

  defp dispatch(target, :enqueue_all, requests) do
    Config.get(:queue_adapter).enqueue_all(target, requests)
  end

  defp dispatch(target, operation, [[queue, worker, args, options]])
       when operation in [:enqueue, :enqueue_at, :enqueue_in] do
    {schedule, options} = Keyword.pop(options, :schedule)
    adapter = Config.get(:queue_adapter)

    case schedule do
      nil -> adapter.enqueue(target, queue, worker, args, options)
      {:at, time} -> adapter.enqueue_at(target, queue, time, worker, args, options)
      {:in, offset} -> adapter.enqueue_in(target, queue, offset, worker, args, options)
    end
  end
end
