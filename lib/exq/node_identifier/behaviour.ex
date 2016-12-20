defmodule Exq.NodeIdentifier.Behaviour do
  use Behaviour

  @callback node_id() :: String.t
end
