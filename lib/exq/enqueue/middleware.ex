defmodule Exq.Enqueue.Middleware do
  @moduledoc """
  Caller-side middleware configured with `config :exq, enqueue_middleware: [MyMiddleware]`.

  Middleware runs in configuration order, with the first module outermost.
  The chain runs once per enqueue request, including bulk requests.
  """

  @doc """
  Wraps an enqueue operation in the calling process.

  Call `next.(pipeline)` to enqueue the jobs through the remaining middleware.
  It returns the enqueue result, such as `{:ok, jid}` or `{:error, reason}`, which
  you should return to the caller. To reject the request instead, return an error
  such as `{:error, :blocked}` without calling `next`.

  Jobs and their options are editable; pass the updated pipeline to `next`.
  See `Exq.Enqueue.Pipeline` for the request structure.

  ## Restrictions

  * When `pipeline.operation` is not `:enqueue_all`, `jobs` must contain exactly one pair.
  * Job timestamps, retry counts, failure details, and other adapter-managed fields
    cannot be overridden through the job struct; changes to them are not forwarded.
  * Options cannot override the job's `jid`, `meta`, `retry`, `unique_for`, or
    `unique_until` (`max_retries` comes from `job.retry`). A non-nil `job.unique_token`
    also overrides `options[:unique_token]`.
  * Changing queue, class, or arguments does not recalculate the uniqueness token.
  * Metadata keys must be strings and cannot override built-in job fields.

  Exceptions and exits from middleware propagate to the caller. Exq does not roll
  back a completed adapter write if middleware subsequently fails.

  ## Example

  Apply a retry limit to a particular worker:

      defmodule RetryLimits do
        @behaviour Exq.Enqueue.Middleware

        def around_enqueue(pipeline, next) do
          jobs =
            Enum.map(pipeline.jobs, fn {job, options} ->
              retries = if job.class == "MyApp.EmailWorker", do: 5, else: job.retry
              {%{job | retry: retries}, options}
            end)

          next.(%{pipeline | jobs: jobs})
        end
      end

  Configure with `config :exq, enqueue_middleware: [RetryLimits]`.
  """
  @callback around_enqueue(Exq.Enqueue.Pipeline.t(), (Exq.Enqueue.Pipeline.t() -> tuple())) ::
              tuple()
end
