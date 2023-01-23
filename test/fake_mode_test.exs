defmodule FakeModeTest do
  use ExUnit.Case, async: true
  alias Exq.Support.Time

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
      scheduled_at = DateTime.utc_now()
      assert [] = Exq.Mock.jobs()
      assert {:ok, _} = Exq.enqueue(Exq, "low", BrokenWorker, [1])
      assert {:ok, _} = Exq.enqueue_at(Exq, "low", scheduled_at, BrokenWorker, [2])
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
                 queue: "low",
                 enqueued_at: ^scheduled_at
               },
               %Exq.Support.Job{
                 args: [3],
                 class: FakeModeTest.BrokenWorker,
                 queue: "low",
                 enqueued_at: scheduled_in
               }
             ] = Exq.Mock.jobs()

      scheduled_seconds = Time.unix_seconds(scheduled_in)
      current_seconds = Time.unix_seconds(DateTime.utc_now())

      assert current_seconds + 290 < scheduled_seconds
      assert current_seconds + 310 > scheduled_seconds
    end

    test "enqueue_all" do
      scheduled_at = DateTime.utc_now()
      assert [] = Exq.Mock.jobs()

      assert [{:ok, _}, {:ok, _}, {:ok, _}] = Exq.enqueue_all(Exq, [
        ["low", BrokenWorker, [1], []],
        ["low", BrokenWorker, [2], [schedule: {:at, scheduled_at}]],
        ["low", BrokenWorker, [3], [schedule: {:in, 300}]]
      ])

      assert [
        %Exq.Support.Job{
          args: [1],
          class: FakeModeTest.BrokenWorker,
          queue: "low"
        },
        %Exq.Support.Job{
          args: [2],
          class: FakeModeTest.BrokenWorker,
          queue: "low",
          enqueued_at: ^scheduled_at
        },
        %Exq.Support.Job{
          args: [3],
          class: FakeModeTest.BrokenWorker,
          queue: "low",
          enqueued_at: scheduled_in
        }
      ] = Exq.Mock.jobs()

      scheduled_seconds = Time.unix_seconds(scheduled_in)
      current_seconds = Time.unix_seconds(DateTime.utc_now())

      assert current_seconds + 290 < scheduled_seconds
      assert current_seconds + 310 > scheduled_seconds
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
