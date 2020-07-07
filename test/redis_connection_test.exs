defmodule RedisConnectionTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  
  test "handle_response/2" do
    expected = {:error, %Redix.ConnectionError{reason: :disconnected}}
    logs = capture_log(fn ->
      assert expected == Exq.Redis.Connection.handle_response(expected, make_ref())
    end)
    assert logs == ""
  end
end
