defmodule Exq.Adapters.Queue.Mock do
  @moduledoc """
  Mock queue. Designed to be used when testing your application.
  """

  @behaviour Exq.Adapters.Queue

  defdelegate enqueue(pid, queue, worker, args, options), to: Exq.Mock

  defdelegate enqueue_at(pid, queue, time, worker, args, options), to: Exq.Mock

  defdelegate enqueue_in(pid, queue, offset, worker, args, options), to: Exq.Mock
end
