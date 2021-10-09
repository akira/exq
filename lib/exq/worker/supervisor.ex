defmodule Exq.Worker.Supervisor do
  @moduledoc """
  Supervisor for Exq Worker.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: supervisor_name(opts[:name]))
  end

  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def supervisor_name(name) do
    name = name || Exq.Support.Config.get(:name)
    "#{name}.Worker.Sup" |> String.to_atom()
  end

  def start_child(sup, args, opts) do
    shutdown_timeout = Keyword.get(opts, :shutdown_timeout)

    spec = %{
      id: Exq.Worker.Server,
      start: {Exq.Worker.Server, :start_link, args},
      restart: :temporary,
      shutdown: shutdown_timeout
    }

    DynamicSupervisor.start_child(sup, spec)
  end

  def workers(sup) do
    DynamicSupervisor.which_children(sup)
  end

  def workers_count(sup) do
    DynamicSupervisor.count_children(sup)
    |> Map.get(:active)
  end
end
