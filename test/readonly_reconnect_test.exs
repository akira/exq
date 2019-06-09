defmodule ReadonlyReconnectTest do
  use ExUnit.Case
  import ExqTestUtil

  setup do
    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)
    :ok
  end

  test "test disconnect on read-only errors with single command" do
    Process.flag(:trap_exit, true)
    {:ok, redis} = Redix.start_link(host: "127.0.0.1", port: 6556)
    Process.register(redis, :testredis)

    Exq.Redis.Connection.q(:testredis, ["SET", "key", "value"])
    assert_received({:EXIT, pid, :killed})
    assert redis == pid
  end

  test "test disconnect on read-only errors with command pipeline" do
    Process.flag(:trap_exit, true)
    {:ok, redis} = Redix.start_link(host: "127.0.0.1", port: 6556)
    Process.register(redis, :testredis)

    Exq.Redis.Connection.qp(:testredis, [["GET", "key"], ["SET", "key", "value"]])
    assert_received({:EXIT, pid, :killed})
    assert redis == pid
  end
end
