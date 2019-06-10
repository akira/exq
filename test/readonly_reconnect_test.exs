defmodule ReadonlyReconnectTest do
  use ExUnit.Case
  import ExqTestUtil

  setup do
    Process.flag(:trap_exit, true)
    {:ok, redis} = Redix.start_link(host: "127.0.0.1", port: 6556)
    Process.register(redis, :testredis)

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)

    {:ok, redis: redis}
  end

  test "disconnect on read-only errors with single command", %{redis: redis} do
    Exq.Redis.Connection.q(:testredis, ["SET", "key", "value"])
    assert_received({:EXIT, pid, :killed})
    assert redis == pid
  end

  test "disconnect on read-only errors with command pipeline", %{redis: redis} do
    Exq.Redis.Connection.qp(:testredis, [["GET", "key"], ["SET", "key", "value"]])
    assert_received({:EXIT, pid, :killed})
    assert redis == pid
  end

  test "disconnect on read-only errors with command pipeline returning values", %{redis: redis} do
    Exq.Redis.Connection.qp!(:testredis, [["GET", "key"], ["SET", "key", "value"]])
    assert_received({:EXIT, pid, :killed})
    assert redis == pid
  end

  test "pass through other errors" do
    assert {:error, %Redix.Error{}} = Exq.Redis.Connection.q(:testredis, ["GETS", "key"])
    assert {:ok, [%Redix.Error{}]} = Exq.Redis.Connection.qp(:testredis, [["GETS", "key"]])
  end
end
