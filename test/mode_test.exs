defmodule ModeTest do
  use ExUnit.Case

  test "supervisor waits for worker drainer to terminate" do
    children = Exq.Support.Mode.children(shutdown_timeout: 10_000)

    worker_drainer_child_spec = find_child(children, Exq.WorkerDrainer.Server)
    assert %{shutdown: 10_000} = worker_drainer_child_spec
  end

  defp find_child(children, child_id) do
    Enum.find(children, fn %{id: id} -> id == child_id end)
  end
end
