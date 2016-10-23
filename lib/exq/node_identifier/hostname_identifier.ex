defmodule Exq.NodeIdentifier.HostnameIdentifier do
  @behaviour Exq.NodeIdentifier.Behaviour

  def node_id(hostname) do
    hostname
  end
end
