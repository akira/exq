defmodule Exq.Enqueuer do
  @moduledoc """
  Enqueuer
  """

  # Mixin EnqueueApi
  use Exq.Enqueuer.EnqueueApi

  def start(opts \\ []) do
    Exq.Enqueuer.Supervisor.start_link(opts)
  end

  def start_link(opts \\ []) do
    Exq.Enqueuer.Supervisor.start_link(opts)
  end
end
