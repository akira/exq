defmodule Exq.Dequeue.Local do
  @behaviour Exq.Dequeue.Behaviour

  defmodule State do
    defstruct max: nil, current: 0
  end

  def init(%{queue: queue}, %{concurrency: concurrency}) do
    {:ok, %State{max: concurrency}}
  end

  def stop(_), do: {:ok, nil}

  def available?(state), do: {:ok, state.current < state.max, state}

  def dispatched(state), do: {:ok, %{state | current: state.current + 1}}

  def processed(state), do: {:ok, %{state | current: state.current - 1}}

  def failed(state), do: {:ok, %{state | current: state.current - 1}}
end
