defmodule InlineAdapterTest do
  use ExUnit.Case, async: true

  defmodule EchoWorker do
    def perform(value), do: value
  end

  setup do
    Exq.Mock.set_mode(:inline)
  end

  describe "inline mode" do
    test "enqueue should return the correct value" do
      assert {:ok, _} = Exq.enqueue(Exq, "low", EchoWorker, [1])
    end

    test "enqueue_at should return the correct value" do
      assert {:ok, _} = Exq.enqueue_at(Exq, "low", DateTime.utc_now(), EchoWorker, [1])
    end

    test "enqueue_in should return the correct value" do
      assert {:ok, _} = Exq.enqueue_in(Exq, "low", 300, EchoWorker, [1])
    end
  end
end
