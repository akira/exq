defmodule Exq.Manager.Supervisor do
  use Supervisor

  def start(opts \\ []) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts[:name]))
  end

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts[:name]))
  end

  def init([opts]) do
    children = [
      worker(Exq.Manager.Server, [opts]),
      supervisor(Exq.Worker.Supervisor, [opts])
    ]
    supervise(children, strategy: :one_for_one, max_restarts: 20, max_seconds: 5)
  end

  def server_name(nil), do: Exq
  def server_name(name), do: name

  def supervisor_name(nil), do: Exq.Sup
  def supervisor_name(name), do: "#{name}.Sup" |> String.to_atom

end
