defmodule Exq.Enqueuer.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts[:name]))
  end

  def init([opts]) do
    children = [
      worker(Exq.Enqueuer.Server, [Keyword.merge(opts, [name: server_name(opts[:name])])])
      ]
    supervise(children, strategy: :one_for_one, max_restarts: 20)
  end

  def server_name(name, type \\ :normal)

  def server_name(nil, _), do: Exq.Enqueuer
  def server_name(name, :normal), do: name
  def server_name(name, :start_by_manager), do: "#{name}.Enqueuer" |> String.to_atom

  def supervisor_name(nil), do: Exq.Enqueuer.Sup
  def supervisor_name(name), do: "#{name}.Sup" |> String.to_atom

end
