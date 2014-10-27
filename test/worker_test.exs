Code.require_file "test_helper.exs", __DIR__

defmodule WorkerTest do
  use ExUnit.Case

  def perform do
  end
  def perform(a1, a2, a3) do
  end
  def custom_perform do
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
      "{ \"queue\": \"default\", \"class\": \"WorkerTest\", \"args\": [] }")
    assert_terminate(worker, true)
  end
  
  test "execute valid job with perform args" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest\", \"args\": [1, 2, 3] }")
    assert_terminate(worker, true)
  end

  test "execute valid job with custom function" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest/custom_perform\", \"args\": [] }")
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
      "{ \"queue\": \"default\", \"class\": \"WorkerTest/nonexist\", \"args\": [] }")
    assert_terminate(worker, false)
  end



end
