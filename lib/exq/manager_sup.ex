defmodule Exq.Manager.Supervisor do
  use Supervisor

  def start(opts) do
    {:ok, sup} = Supervisor.start_link(__MODULE__, [opts], [])
    {:ok, manager_name(opts)}
  end

  def start_link(opts) do
    {:ok, sup} = Supervisor.start_link(__MODULE__, {opts}, name: :manager_sup)
    {:ok, manager_name(opts)}
  end

  def init({opts}) do
    children = [worker(Exq.Manager, [opts])]
    supervise(children, strategy: :one_for_one, max_restarts: 500, max_seconds: 5)
  end

  defp manager_name(opts) do
    Keyword.get(opts, :name, Exq.Manager.default_name)
  end

end

