defmodule Exq.Dequeue.Behaviour do
  @moduledoc """
  Custom concurrency or rate limiting at a queue level can be achieved
  by implementing the Dequeue behaviour.

  The following config can be used to customize dequeue behaviour for a queue:

      config :exq,
        queues: [{"default", {RateLimiter, options}}]

  RateLimiter module should implement `Exq.Dequeue.Behaviour`. The
  options supplied here would be passed as the second argument to the
  `c:init/2` function.

  ### Life cycle

  `c:init/2` will be invoked on initialization. The first argument will contain info
  like queue and the second argument is user configurable.

  `c:available?/1` will be invoked before each poll. If the
  returned value contains `false` as the second element of the tuple,
  the queue will not polled

  `c:dispatched/1` will be invoked once a job is dispatched to the worker

  `c:processed/1` will be invoked if a job completed successfully

  `c:failed/1` will be invoked if a job failed

  `c:stop/1` will be invoked when a queue is unsubscribed or before the
  node terminates. Note: there is no guarantee this will be invoked if
  the node terminates abruptly
  """

  @callback init(info :: %{queue: String.t()}, args :: term) :: {:ok, term}
  @callback stop(state :: term) :: :ok
  @callback available?(state :: term) :: {:ok, boolean, term}
  @callback dispatched(state :: term) :: {:ok, term}
  @callback processed(state :: term) :: {:ok, term}
  @callback failed(state :: term) :: {:ok, term}
end
