defmodule Exq.Enqueuer.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts))
  end

  def init([opts]) do
    children = [worker(Exq.Enqueuer.Server, [opts])]
    supervise(children, strategy: :one_for_one, max_restarts: 20)
  end

  defp server_name(opts) do
    Keyword.get(opts, :name, Exq.Enqueuer.Server.default_name)
  end

  defp supervisor_name(opts) do
    String.to_atom("#{server_name(opts)}_sup")
  end
end
