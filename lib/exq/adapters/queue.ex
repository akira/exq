defmodule Exq.Adapters.Queue do
  @moduledoc ~S"""
  Behaviour for creating Exq queue adapters.

  ## Example

      defmodule Exq.Adapters.Queue.CustomAdapter do
        @behaviour Exq.Adapters.Queue
        def enqueue(pid, queue, worker, args, options) do
          {:ok, apply(worker, :perform, args)}
        end

        def enqueue_at(pid, queue, time, worker, args, options) do
          enqueue_somehow(pid, queue, time, worker, args, options)
        end

        def enqueue_in(pid, queue, offset, worker, args, options) do
          enqueue_in_somehow(pid, queue, offset, worker, args, options)
        end
      end

  """

  @typedoc "The GenServer name"
  @type name :: atom | {:global, term} | {:via, module, term}

  @typedoc "The server reference"
  @type server :: pid | name | {atom, node}

  @callback enqueue(server, String.t(), module(), list(), list()) :: tuple()
  @callback enqueue_at(server, String.t(), DateTime.t(), module(), list(), list()) :: tuple()
  @callback enqueue_in(server, String.t(), integer(), module(), list(), list()) :: tuple()
  @callback enqueue_all(server, list()) :: tuple()
end
