defmodule Exq.Enqueuer.EnqueueApi do
  @moduledoc """
  Enqueue API.

  Expects a Exq.Manager.Server or Exq.Enqueuer.Server process as first arg.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      alias Exq.Support.Config

      @doc """
      Enqueue a job immediately.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker

      Returns:
      * `{:ok, jid}` if the job was enqueued successfully, with `jid` = Job ID.
      * `{:error, reason}` if there was an error enqueueing job
      """
      def enqueue(pid, queue, worker, args) do
        GenServer.call(pid, {:enqueue, queue, worker, args}, Config.get(:genserver_timeout))
      end
      def enqueue(pid, from, queue, worker, args) do
        GenServer.cast(pid, {:enqueue, from, queue, worker, args})
      end

      @doc """
      Schedule a job to be enqueued at a specific time in the future.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - name of queue to use
        * `time` - Time to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
      """
      def enqueue_at(pid, queue, time, worker, args) do
        GenServer.call(pid, {:enqueue_at, queue, time, worker, args}, Config.get(:genserver_timeout))
      end
      def enqueue_at(pid, from, queue, time, worker, args) do
        GenServer.cast(pid, {:enqueue_at, from, queue, time, worker, args})
      end

      @doc """
      Schedule a job to be enqueued at in the future given by offset in milliseconds.

      Expected args:
        * `pid` - PID for Exq Manager or Enqueuer to handle this
        * `queue` - Name of queue to use
        * offset - Offset in milliseconds in the future to enqueue
        * `worker` - Worker module to target
        * `args` - Array of args to send to worker
      """
      def enqueue_in(pid, queue, offset, worker, args) do
        GenServer.call(pid, {:enqueue_in, queue, offset, worker, args}, Config.get(:genserver_timeout))
      end
      def enqueue_in(pid, from, queue, offset, worker, args) do
        GenServer.cast(pid, {:enqueue_in, from, queue, offset, worker, args})
      end
    end
  end
end
