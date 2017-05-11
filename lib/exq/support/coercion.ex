defmodule Exq.Support.Coercion do
  @moduledoc false

  def to_integer(value) when is_integer(value) do
    value
  end

  def to_integer(binary) when is_binary(binary) do
    binary
    |> Integer.parse()
    |> case do
      {integer, ""} ->
        integer

      _ ->
        raise ArgumentError,
          message: "Failed to parse #{inspect(binary)} into an integer."
    end
  end

  def to_integer(value) do
    raise ArgumentError,
      message: "Failed to parse #{inspect(value)} into an integer."
  end
end
