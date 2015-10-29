defmodule Exq.Stats.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, [opts], name: String.to_atom("#{manager_name(opts)}_sup"))
  end

  def init([opts]) do
    children = [worker(Exq.Stats.Server, [opts])]
    supervise(children, strategy: :one_for_one, max_restarts: 20)
  end

  defp manager_name(opts) do
    Keyword.get(opts, :name, Exq.Stats.Server.default_name)
  end
end
