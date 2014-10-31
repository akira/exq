Code.require_file "test_helper.exs", __DIR__

defmodule WorkerTest do
  use ExUnit.Case

  defmodule NoArgWorker do
    def perform do
    end
  end

  defmodule ThreeArgWorker do
    def perform(a1, a2, a3) do
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
    Exq.Worker.work(worker)
    receive do
      {:'DOWN', ref, _, _pid, :normal} -> assert normal_terminate
      {:'DOWN', ref, _, _pid, _} -> assert !normal_terminate
    after_timeout ->
      assert !normal_terminate
    end
  end

  test "execute valid job with perform" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest.NoArgWorker\", \"args\": [] }")
    assert_terminate(worker, true)
  end

  test "execute valid job with perform args" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest.ThreeArgWorker\", \"args\": [1, 2, 3] }")
    assert_terminate(worker, true)
  end

  test "execute valid job with custom function" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest.CustomMethodWorker/custom_perform\", \"args\": [] }")
    assert_terminate(worker, true)
  end

  test "execute job with invalid JSON" do
    {:ok, worker} = Exq.Worker.start(
      "{ invalid: json: this: is}")
    assert_terminate(worker, false)
  end

  test "execute invalid module perform" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"NonExistant\", \"args\": [] }")
    assert_terminate(worker, false)
  end

  test "execute invalid module function" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest.MissingMethodWorker/nonexist\", \"args\": [] }")
    assert_terminate(worker, false)
  end



end
