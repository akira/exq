defmodule JobTest do
  use ExUnit.Case

  alias Exq.Support.Job

  test "meta cannot overwrite any built-in payload field" do
    for key <- Job.payload_fields() do
      assert_raise ArgumentError, "meta cannot override job field #{inspect(key)}", fn ->
        Job.encode(%Job{meta: %{key => "override"}})
      end
    end
  end

  test "meta requires a map with string keys" do
    for meta <- [nil, [], %{tenant_id: "tenant-1"}, DateTime.utc_now()] do
      assert_raise ArgumentError,
                   "meta must be a map with string keys",
                   fn -> Job.encode(%Job{meta: meta}) end
    end
  end

  test "metadata values use the configured encoder" do
    values = [:ready, %{state: :ready}, [%{enabled: true}], ~U[2026-01-01 00:00:00Z]]

    for library <- [Jason, Poison] do
      ExqTestUtil.with_application_env(:exq, :json_library, library, fn ->
        meta = %{"values" => values}
        assert Job.validate_meta!(meta) == meta
        job = Job.decode(Job.encode(%Job{args: values, meta: meta}))
        assert job.meta["values"] == job.args

        assert job.args == [
                 "ready",
                 %{"state" => "ready"},
                 [%{"enabled" => true}],
                 "2026-01-01T00:00:00Z"
               ]
      end)
    end
  end

  test "unsupported metadata values fail through the encoder" do
    value = make_ref()
    meta = %{"value" => value}
    assert Job.validate_meta!(meta) == meta

    for {library, error} <- [{Jason, Protocol.UndefinedError}, {Poison, Poison.EncodeError}] do
      ExqTestUtil.with_application_env(:exq, :json_library, library, fn ->
        assert_raise error, fn -> Job.encode(%Job{meta: meta}) end
      end)
    end
  end

  test "enqueue APIs validate meta in the caller before reaching an adapter" do
    options = [meta: %{"jid" => "override"}]

    calls = [
      fn -> Exq.enqueue(:not_started, "default", MyWorker, [], options) end,
      fn ->
        Exq.enqueue_at(:not_started, "default", DateTime.utc_now(), MyWorker, [], options)
      end,
      fn -> Exq.enqueue_in(:not_started, "default", 60, MyWorker, [], options) end,
      fn ->
        Exq.enqueue_all(:not_started, [
          ["default", MyWorker, [], []],
          ["default", MyWorker, [], options]
        ])
      end
    ]

    for call <- calls do
      assert_raise ArgumentError, ~s(meta cannot override job field "jid"), call
    end
  end
end
