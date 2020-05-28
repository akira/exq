defmodule FakeModeTest do
  use ExUnit.Case, async: true

  defmodule BrokenWorker do
    def perform(_) do
      raise RuntimeError, "Unexpected"
    end
  end

  setup do
    Exq.Mock.set_mode(:fake)
  end

  describe "fake mode" do
    test "enqueue" do
      assert [] = Exq.Mock.jobs()
      assert {:ok, _} = Exq.enqueue(Exq, "low", BrokenWorker, [1])
      assert {:ok, _} = Exq.enqueue_at(Exq, "low", DateTime.utc_now(), BrokenWorker, [2])
      assert {:ok, _} = Exq.enqueue_in(Exq, "low", 300, BrokenWorker, [3])

      assert [
               %Exq.Support.Job{
                 args: [1],
                 class: FakeModeTest.BrokenWorker,
                 queue: "low"
               },
               %Exq.Support.Job{
                 args: [2],
                 class: FakeModeTest.BrokenWorker,
                 queue: "low"
               },
               %Exq.Support.Job{
                 args: [3],
                 class: FakeModeTest.BrokenWorker,
                 queue: "low"
               }
             ] = Exq.Mock.jobs()
    end

    test "with predetermined job ID" do
      jid = UUID.uuid4()

      assert [] = Exq.Mock.jobs()
      assert {:ok, jid} == Exq.enqueue(Exq, "low", BrokenWorker, [], jid: jid)

      assert [
               %Exq.Support.Job{
                 args: [],
                 class: FakeModeTest.BrokenWorker,
                 queue: "low",
                 jid: ^jid
               }
             ] = Exq.Mock.jobs()
    end
  end
end
