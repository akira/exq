defmodule Exq.Scheduler.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts[:name]))
  end

  def init([opts]) do
    children = [
      worker(Exq.Scheduler.Server, [Keyword.merge(opts, [name: server_name(opts[:name])])])
      ]
    supervise(children, strategy: :one_for_one, max_restarts: 20)
  end

  def server_name(nil), do: Exq.Scheduler.Server
  def server_name(name), do: "#{name}.Scheduler.Server" |> String.to_atom

  def supervisor_name(nil), do: Exq.Scheduler.Sup
  def supervisor_name(name), do: "#{name}.Scheduler.Sup" |> String.to_atom

end
