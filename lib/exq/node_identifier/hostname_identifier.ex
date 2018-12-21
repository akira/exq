defmodule Exq.NodeIdentifier.HostnameIdentifier do
  @behaviour Exq.NodeIdentifier.Behaviour

  def node_id do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end
end
