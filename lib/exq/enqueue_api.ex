defmodule Exq.Enqueuer.EnqueueApi do
  @moduledoc """
  Enqueue API.

  Expects a Exq.Manager.Server or Exq.Enqueuer.Server process as first arg.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      alias Exq.Support.Config

      @default_options []
      @doc """
      Enqueue a job immediately.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
        * `options` - job options, for example [max_retries: `Integer`, jid: `String`]

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
      Enqueue several jobs immediately.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `worker` - Worker module to target
        * `args` - Array of array of args to send to workers
        * `options` - job options, for example [max_retries: `Integer`].
        jid is not supported.

      Returns:
        * `{:ok, jids}` if jobs were enqueued successfully, with `jids` = Job IDs.
        * `{:error, reason}` if there was an error enqueueing job

      """
      def enqueue_bulk(pid, queue, worker, args),
        do: enqueue_bulk(pid, queue, worker, args, @default_options)

      def enqueue_bulk(pid, queue, worker, args, options) do
        queue_adapter = Config.get(:queue_adapter)
        queue_adapter.enqueue_bulk(pid, queue, worker, args, options)
      end

      @doc """
      Schedule a job to be enqueued at a specific time in the future.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - name of queue to use
        * `time` - Time to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
        * `options` - job options, for example [max_retries: `Integer`, jid: `String`]

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
        * `options` - job options, for example [max_retries:  `Integer`]

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
    end
  end
end
