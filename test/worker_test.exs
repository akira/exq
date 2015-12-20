Code.require_file "test_helper.exs", __DIR__

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

  def assert_terminate(worker, normal_terminate) do
    :erlang.monitor(:process, worker)
    Exq.Worker.Server.work(worker)
    receive do
      {:'DOWN', _, _, _pid, :normal} -> assert normal_terminate
      {:'DOWN', _, _, _pid, _} -> assert !normal_terminate
    _ ->
      assert !normal_terminate
    end
  end

  def start_worker(job) do
    work_table = :ets.new(:work_table, [:set, :public])
    Exq.Worker.Server.start(job, nil, "default", work_table, spawn(fn -> end), "exq", "localhost")
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

  test "execute valid job with custom function" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.CustomMethodWorker/custom_perform\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute job with invalid JSON" do
    {:ok, worker} = start_worker("{ invalid: json: this: is}")
    assert_terminate(worker, false)
  end

  test "execute invalid module perform" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"NonExistant\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute invalid module function" do
    {:ok, worker} = start_worker("{ \"queue\": \"default\", \"class\": \"WorkerTest.MissingMethodWorker/nonexist\", \"args\": [] }")
    assert_terminate(worker, false)
  end
end
