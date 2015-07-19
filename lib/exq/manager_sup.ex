defmodule Exq.Manager.Supervisor do
  use Supervisor

  def start(opts \\ []) do
    Supervisor.start_link(__MODULE__, {opts}, name: supervisor_name(opts))
  end

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, {opts}, name: supervisor_name(opts))
  end

  def init({opts}) do
    children = [worker(Exq.Manager, [opts])]
    supervise(children, strategy: :one_for_one, max_restarts: 500, max_seconds: 5)
  end

  defp manager_name(opts) do
    Keyword.get(opts, :name, Exq.Manager.default_name)
  end

  defp supervisor_name(opts) do
    String.to_atom("#{manager_name(opts)}_sup")
  end
end
