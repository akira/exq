defmodule Exq.Enqueuer.EnqueueApi do
  @moduledoc """
  Enqueue API.

  Expects a Exq.Manager.Server or Exq.Enqueuer.Server process as first arg.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      alias Exq.Support.Config
      alias Exq.Redis.JobQueue

      @default_options []
      @doc """
      Enqueue a job immediately.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
        * `options` - job options, for example [max_retries:  `Integer`]

      Returns:
      * `{:ok, jid}` if the job was enqueued successfully, with `jid` = Job ID.
      * `{:error, reason}` if there was an error enqueueing job
      """
      def enqueue(pid, queue, worker, args),
        do: enqueue(pid, queue, worker, args, @default_options)

      def enqueue(pid, queue, worker, args, options) do
        {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
        JobQueue.enqueue(redis, namespace, queue, worker, args, options)
      end

      @doc """
      Schedule a job to be enqueued at a specific time in the future.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - name of queue to use
        * `time` - Time to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
        * `options` - job options, for example [max_retries:  `Integer`]

      """
      def enqueue_at(pid, queue, time, worker, args),
        do: enqueue_at(pid, queue, time, worker, args, @default_options)

      def enqueue_at(pid, queue, time, worker, args, options) do
        {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
        JobQueue.enqueue_at(redis, namespace, queue, time, worker, args, options)
      end

      @doc """
      Schedule a job to be enqueued at in the future given by offset in milliseconds.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `offset` - Offset in seconds in the future to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
        * `options` - job options, for example [max_retries:  `Integer`]

      """
      def enqueue_in(pid, queue, offset, worker, args),
        do: enqueue_in(pid, queue, offset, worker, args, @default_options)

      def enqueue_in(pid, queue, offset, worker, args, options) do
        {redis, namespace} = GenServer.call(pid, :redis, Config.get(:genserver_timeout))
        JobQueue.enqueue_in(redis, namespace, queue, offset, worker, args, options)
      end
    end
  end
end
