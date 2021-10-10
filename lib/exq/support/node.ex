defmodule Exq.Support.Node do
  @moduledoc """
  Struct for node.
  """
  defstruct hostname: nil,
            identity: nil,
            started_at: nil,
            pid: nil,
            queues: [],
            labels: [],
            tag: "",
            busy: 0,
            concurrency: 0,
            quiet: false

  alias Exq.Support.Config

  @doc """
  Serialize node to JSON.
  """
  def encode(%__MODULE__{} = node) do
    Config.serializer().encode_node(node)
  end

  @doc """
  Decode JSON into node.
  """
  def decode(serialized) do
    Config.serializer().decode_node(serialized)
  end
end
