defmodule Exq.Worker.Supervisor do
  import Supervisor.Spec

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, [name: supervisor_name(opts[:name])])
  end

  def init(_arg) do
    children = [
      worker(Exq.Worker.Server, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  def supervisor_name(name) do
    unless name, do: name = Exq.Support.Config.get(:name, Exq)
    "#{name}.Worker.Sup" |> String.to_atom
  end

  def start_child(sup, args) do
    Supervisor.start_child(sup, args)
  end
end