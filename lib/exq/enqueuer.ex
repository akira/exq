defmodule Exq.Enqueuer do
  @moduledoc """
  Enqueuer.
  """

  # Mixin EnqueueApi
  use Exq.Enqueuer.EnqueueApi

  def start_link(opts \\ []) do
    Exq.start_link(Keyword.put(opts, :mode, :enqueuer))
  end
end
