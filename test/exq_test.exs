Code.require_file "test_helper.exs", __DIR__

defmodule ExqTest do
  use ExUnit.Case

  def perform do
    send :exqtest, {:worked}
  end

  def perform(arg) do
    send :exqtest, {:worked, arg}
  end

  setup do
    TestRedis.start
    IO.puts "Start"
    on_exit fn ->
      TestRedis.stop
    end
    :ok
  end

  test "enqueue with pid" do
    {:ok, exq} = Exq.start([port: 6555 ])
    {:ok, _} = Exq.enqueue(exq, "default", "MyJob", [1, 2, 3])
    Exq.stop(exq)
    :timer.sleep(10)
  end

  test "run job" do
    Process.register(self, :exqtest)
    {:ok, exq} = Exq.start([port: 6555, poll_timeout: 1 ])
    {:ok, _} = Exq.enqueue(exq, "default", "ExqTest", [])
    :timer.sleep(50)
    assert_received {:worked}
    Exq.stop(exq)
    :timer.sleep(10)
  end

  test "run jobs on multiple queues" do
    Process.register(self, :exqtest)
    {:ok, exq} = Exq.start_link([port: 6555, queues: ["q1", "q2"], poll_timeout: 1])
    {:ok, _} = Exq.enqueue(exq, "q1", "ExqTest", [1])
    {:ok, _} = Exq.enqueue(exq, "q2", "ExqTest", [2])
    :timer.sleep(50)
    assert_received {:worked, 1}
    assert_received {:worked, 2}
    Exq.stop(exq)
    :timer.sleep(10)
  end
end
