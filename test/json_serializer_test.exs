defmodule Exq.Serializers.JsonSerializer.Test do
  use ExUnit.Case
  alias Exq.Serializers.JsonSerializer
  alias Exq.Support.Job

  test "encode" do
    map = %{}
    json = "{}"
    assert JsonSerializer.encode(map) == {:ok, json}
  end

  test "encode!" do
    map = %{}
    json = "{}"
    assert JsonSerializer.encode!(map) == json
  end

  test "decode" do
    map = %{}
    json = "{}"
    assert JsonSerializer.decode(json) == {:ok, map}
  end

  test "decode!" do
    map = %{}
    json = "{}"
    assert JsonSerializer.decode!(json) == map
  end

  test "jobs without additional fields have empty meta" do
    assert %Job{meta: %{}} = Job.decode(~s({"class":"MyWorker","args":[]}))
    refute Map.has_key?(JsonSerializer.decode!(Job.encode(%Job{})), "meta")
  end

  test "unknown payload fields round-trip through meta" do
    payload = %{
      "class" => "MyWorker",
      "args" => [42],
      "queue" => "default",
      "jid" => "123",
      "traceparent" => "00-trace-span-01",
      "tenant_id" => "tenant-1",
      "tags" => ["billing"],
      "custom" => %{"enabled" => true, "values" => [nil, 1, 1.5]}
    }

    for library <- [Jason, Poison] do
      ExqTestUtil.with_application_env(:exq, :json_library, library, fn ->
        job = payload |> JsonSerializer.encode!() |> Job.decode()
        assert job.meta == Map.drop(payload, ["class", "args", "queue", "jid"])
        assert job.args == [42]

        encoded = job |> Job.encode() |> JsonSerializer.decode!()
        assert Map.take(encoded, Map.keys(payload)) == payload
        refute Map.has_key?(encoded, "meta")
      end)
    end
  end

  test "both struct and map jobs encode meta at the payload top level" do
    meta = %{"tenant_id" => "tenant-1"}
    job = %Job{class: "MyWorker", args: [42], meta: meta}

    for value <- [job, Map.from_struct(job)] do
      encoded = value |> Job.encode() |> JsonSerializer.decode!()
      assert encoded["tenant_id"] == "tenant-1"
      refute Map.has_key?(encoded, "meta")
      assert Job.decode(Job.encode(value)).meta == meta
    end
  end

  test "meta is not a reserved wire field" do
    job = Job.decode(~s({"class":"MyWorker","args":[],"meta":{"custom":true}}))
    assert job.meta == %{"meta" => %{"custom" => true}}
    assert JsonSerializer.decode!(Job.encode(job))["meta"] == %{"custom" => true}
  end
end
