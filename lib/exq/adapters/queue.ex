defmodule Exq.Adapters.Queue do
  @moduledoc false

  @callback enqueue(any(), String.t(), module(), list(), list()) :: tuple()
  @callback enqueue(any(), any(), String.t(), module(), list(), list()) :: tuple()
  @callback enqueue_at(any(), String.t(), any(), module(), list(), list()) :: tuple()
  @callback enqueue_at(any(), any(), String.t(), any(), module(), list(), list()) :: tuple()
  @callback enqueue_in(any(), String.t(), any(), module(), list(), list()) :: tuple()
  @callback enqueue_in(any(), any(), String.t(), any(), module(), list(), list()) :: tuple()
end
