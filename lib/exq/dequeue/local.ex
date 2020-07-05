defmodule Exq.Dequeue.Local do
  @behaviour Exq.Dequeue.Behaviour

  defmodule State do
    defstruct max: nil, current: 0
  end

  @impl true
  def init(%{queue: queue}, %{concurrency: concurrency}) do
    {:ok, %State{max: concurrency}}
  end

  @impl true
  def stop(_), do: :ok

  @impl true
  def available?(state), do: {:ok, state.current < state.max, state}

  @impl true
  def dispatched(state), do: {:ok, %{state | current: state.current + 1}}

  @impl true
  def processed(state), do: {:ok, %{state | current: state.current - 1}}

  @impl true
  def failed(state), do: {:ok, %{state | current: state.current - 1}}
end
