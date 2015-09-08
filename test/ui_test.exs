defmodule Exq.ApiTest do
  use ExUnit.Case, async: false
  use Plug.Test
  alias Exq.Support.Json
  import ExqTestUtil

  setup_all do
    TestRedis.setup
    {:ok, sup} = Exq.Enqueuer.start_link([name: :exq_ui_enqueuer])
    on_exit fn ->
      TestRedis.teardown
      stop_process(sup)
    end
    :ok
  end

  defp call(conn) do
    conn
    |> assign(:exq_name, :exq_ui_enqueuer)
    |> Exq.RouterPlug.Router.call([])
 end

  test "serves the index" do
    conn = conn(:get, "/") |> call
    assert conn.status == 200
  end
  test "serves the stats" do
    conn = conn(:get, "/api/stats/all") |> call
    assert conn.status == 200
  end

  test "serves the failures" do
    conn = conn(:get, "/api/failures") |> call
    assert conn.status == 200
  end

  test "serves the failure" do
    conn = conn(:get, "/api/failures/123") |> call
    assert conn.status == 200
  end

  test "serves the realtime" do
    conn = conn(:get, "/api/realtimes") |> call
    assert conn.status == 200
  end

  test "serves the processes" do
    conn = conn(:get, "/api/processes") |> call
    assert conn.status == 200
    {:ok, json} = Json.decode(conn.resp_body)
    assert json["processes"] == []
  end

  test "serves the queues" do
    conn = conn(:get, "/api/queues") |> call
    assert conn.status == 200
  end

  test "serves the queue" do
    conn = conn(:get, "/api/queues/default") |> call
    assert conn.status == 200
  end
end