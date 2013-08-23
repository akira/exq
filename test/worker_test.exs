Code.require_file "test_helper.exs", __DIR__

defmodule WorkerTest do
  use ExUnit.Case

  def perform do
    IO.puts("PERFORM") 
  end
  def custom_perform do
    IO.puts("CUSTOM_PERFORM") 
  end
  
  def assert_terminate(worker, is_normal) do 
    :erlang.monitor(:process, worker)
    Exq.Worker.work(worker)
    receive do 
      {:'DOWN', ref, _, _pid, :normal} -> assert is_normal
      {:'DOWN', ref, _, _pid, _} -> assert !is_normal
    after_timeout ->
      assert !is_normal
    end 
  end
 
  test "execute valid job with perform" do
    {:ok, worker} = Exq.Worker.start(
      "{ \"queue\": \"default\", \"class\": \"WorkerTest\", \"args\": [] }")
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
