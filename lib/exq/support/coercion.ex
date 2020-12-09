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

  def to_boolean(value) when is_boolean(value) do
    value
  end

  @true_values ["true", "yes", "1"]
  def to_boolean(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      x when x in @true_values -> true
      _ -> false
    end
  end

  def to_boolean(value) do
    raise ArgumentError,
      message: "Failed to parse #{inspect(value)} into a boolean."
  end

  def to_module(class) when is_atom(class) do
    to_module(to_string(class))
  end

  def to_module("Elixir." <> class) do
    to_module(class)
  end

  def to_module(class) do
    target = String.replace(class, "::", ".")
    [mod | _func_or_empty] = Regex.split(~r/\//, target)
    String.to_atom("Elixir.#{mod}")
  end
end
