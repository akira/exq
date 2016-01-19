defmodule WorkerTest do
  use ExUnit.Case

  defmodule NoArgWorker do
    def perform do
    end
  end

  defmodule ThreeArgWorker do
    def perform(_, _, _) do
    end
  end

  defmodule CustomMethodWorker do
    def custom_perform do
    end
  end

  defmodule MissingMethodWorker do
  end

  defmodule RaiseWorker do
    def perform do
      raise "error"
    end
  end

  defmodule SuicideWorker do
    def perform do
      Process.exit(self, :kill)
    end
  end

  def assert_terminate(worker, normal_terminate) do
    Exq.Worker.Server.work(worker)
    if normal_terminate do
      assert_receive {:"$gen_cast", {:record_processed, _, _}}
    else
      assert_receive {:"$gen_cast", {:record_failure, _, _, _}}
    end
  end

  def start_worker(job) do
    work_table = :ets.new(:work_table, [:set, :public])
    Exq.Worker.Server.start_link(job, self, "default", work_table, self, "exq", "localhost", self)
  end

  test "execute valid job with perform" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.NoArgWorker\", \"args\": [] }")
    assert_terminate(worker, true)
  end

  test "execute valid rubyish job with perform" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest::NoArgWorker\", \"args\": [] }")
    assert_terminate(worker, true)
  end

  test "execute valid job with perform args" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.ThreeArgWorker\", \"args\": [1, 2, 3] }")
    assert_terminate(worker, true)
  end

  test "execute worker raising error" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.RaiseWorker\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute valid job with custom function" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.CustomMethodWorker/custom_perform\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute invalid module perform" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"NonExistant\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "worker killed still sends stats" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.SuicideWorker\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute invalid module function" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.MissingMethodWorker/nonexist\", \"args\": [] }")
    assert_terminate(worker, false)
  end
end
