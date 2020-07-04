defmodule Exq.Dequeue.Behaviour do
  @callback init(info :: map, args :: term) :: {:ok, term}
  @callback stop(state :: term) :: {:ok, term}
  @callback available?(state :: term) :: {:ok, boolean, term}
  @callback dispatched(state :: term) :: {:ok, term}
  @callback processed(state :: term) :: {:ok, term}
  @callback failed(state :: term) :: {:ok, term}
end
