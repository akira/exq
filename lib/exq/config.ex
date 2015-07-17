defmodule Exq.Config do
  def get(key, fallback \\ nil) do
    Application.get_env(:exq, key, fallback)
  end
end
