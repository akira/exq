defmodule Exq.Enqueuer.EnqueueApi do
  @moduledoc """
  Enqueue API.

  Expects a Exq.Manager.Server or Exq.Enqueuer.Server process as first arg.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      alias Exq.Support.Config

      @options_doc """
        * `options`: Following job options are supported
          * `max_retries` (integer) - max retry count
          * `jid` (string) - user supplied jid value
          * `unique_for` (integer) - lock expiration duration in seconds
          * `unique_token` (string) - unique lock token. By default the token is computed based on the queue, class and args.
          * `unique_until` (atom) - defaults to `:success`. Supported values are
            * `:success` - unlock on job success
            * `:start` - unlock on job first execution
            * `:expiry` - unlock when the lock is expired. Depends on `unique_for` value.
      """

      @default_options []
      @doc """
      Enqueue a job immediately.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
      #{@options_doc}

      Returns:
        * `{:ok, jid}` if the job was enqueued successfully, with `jid` = Job ID.
        * `{:error, reason}` if there was an error enqueueing job

      """
      def enqueue(pid, queue, worker, args),
        do: enqueue(pid, queue, worker, args, @default_options)

      def enqueue(pid, queue, worker, args, options) do
        queue_adapter = Config.get(:queue_adapter)
        queue_adapter.enqueue(pid, queue, worker, args, options)
      end

      @doc """
      Schedule a job to be enqueued at a specific time in the future.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - name of queue to use
        * `time` - Time to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
      #{@options_doc}

      If Exq is running in `mode: [:enqueuer]`, then you will need to use the Enqueuer
      to schedule jobs, for example:

      ```elixir
      time = Timex.now() |> Timex.shift(days: 8)
      Exq.Enqueuer.enqueue_at(Exq.Enqueuer, "default", time, MyWorker, ["foo"])
      ```
      """
      def enqueue_at(pid, queue, time, worker, args),
        do: enqueue_at(pid, queue, time, worker, args, @default_options)

      def enqueue_at(pid, queue, time, worker, args, options) do
        queue_adapter = Config.get(:queue_adapter)
        queue_adapter.enqueue_at(pid, queue, time, worker, args, options)
      end

      @doc """
      Schedule a job to be enqueued at in the future given by offset in seconds.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `offset` - Offset in seconds in the future to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
      #{@options_doc}

      If Exq is running in `mode: [:enqueuer]`, then you will need to use the Enqueuer
      to schedule jobs, for example:

      ```elixir
      Exq.Enqueuer.enqueue_in(Exq.Enqueuer, "default", 5000, MyWorker, ["foo"])
      ```
      """
      def enqueue_in(pid, queue, offset, worker, args),
        do: enqueue_in(pid, queue, offset, worker, args, @default_options)

      def enqueue_in(pid, queue, offset, worker, args, options) do
        queue_adapter = Config.get(:queue_adapter)
        queue_adapter.enqueue_in(pid, queue, offset, worker, args, options)
      end

      @doc """
      Schedule multiple jobs to be atomically enqueued at specific times

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `jobs` - List of jobs each defined as `[queue, worker, args, options]`
          * `queue` - Name of queue to use
          * `worker` - Worker module to target
          * `args` - Array of args to send to worker
          * `options`: Following job options are supported
            * `max_retries` (integer) - max retry count
            * `jid` (string) - user supplied jid value
            * `unique_for` (integer) - lock expiration duration in seconds
            * `unique_token` (string) - unique lock token. By default the token is computed based on the queue, class and args.
            * `unique_until` (atom) - defaults to `:success`. Supported values are
              * `:success` - unlock on job success
              * `:start` - unlock on job first execution
              * `:expiry` - unlock when the lock is expired. Depends on `unique_for` value.
            * `schedule` - (optional) - used to schedule the job for future. If not present, job will be enqueued immediately by default.
              * `{:in, seconds_from_now}`
              * `{:at, datetime}`

      """
      def enqueue_all(pid, jobs) do
        queue_adapter = Config.get(:queue_adapter)
        queue_adapter.enqueue_all(pid, jobs)
      end
    end
  end
end
