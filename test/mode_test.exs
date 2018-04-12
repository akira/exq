defmodule ModeTest do
  use ExUnit.Case

  test "supervisor waits for worker drainer to terminate" do
    children = Exq.Support.Mode.children([shutdown_timeout: 10_000])

    worker_drainer_child_spec = find_child(children, Exq.WorkerDrainer.Server)
    assert {_id, _start, _restart, 10_000, _type, _module} = worker_drainer_child_spec
  end

  defp find_child(children, child_id) do
    Enum.find(children, fn({id, _, _, _, _, _}) -> id == child_id end)
  end
end
