defmodule Exq.Serializers.JsonSerializer.Test do
  use ExUnit.Case
  alias Exq.Serializers.JsonSerializer

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
end
