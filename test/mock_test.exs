defmodule Exq.MockTest do
  use ExUnit.Case, async: true

  describe "to_job" do
    test "populates job information" do
      start = DateTime.utc_now()

      job = Exq.Mock.to_job([Exq, "default", "Worker", ["args"], []])

      assert job.queue == "default"
      assert job.class == "Worker"
      assert job.args == ["args"]
      assert DateTime.compare(job.enqueued_at, start) != :lt
    end

    test "uses any :jid provided as the job's ID" do
      job = Exq.Mock.to_job([Exq, "default", "Worker", ["args"], [jid: "abcd"]])

      assert job.jid == "abcd"
    end
  end
end
