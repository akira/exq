defmodule AdaptersTest do
  use ExUnit.Case

  alias Exq.Adapters.Queue.Test, as: QueueTest

  defmodule EchoWorker do
    def perform(value), do: value
  end

  describe "Exq.Adapters.Queue.Test" do
    test "enqueue/5 should return the correct value" do
      assert {:ok, 1} == QueueTest.enqueue(nil, nil, EchoWorker, [1], nil)
    end

    test "enqueue/6 should return the correct value" do
      assert {:ok, 2} == QueueTest.enqueue(nil, nil, nil, EchoWorker, [2], nil)
    end

    test "enqueue_at/6 should return the correct value" do
      assert {:ok, 3} == QueueTest.enqueue_at(nil, nil, nil, EchoWorker, [3], nil)
    end

    test "enqueue_at/7 should return the correct value" do
      assert {:ok, 4} == QueueTest.enqueue_at(nil, nil, nil, nil, EchoWorker, [4], nil)
    end

    test "enqueue_in/6 should return the correct value" do
      assert {:ok, 5} == QueueTest.enqueue_in(nil, nil, nil, EchoWorker, [5], nil)
    end

    test "enqueue_in/7 should return the correct value" do
      assert {:ok, 6} == QueueTest.enqueue_in(nil, nil, nil, nil, EchoWorker, [6], nil)
    end
  end
end
