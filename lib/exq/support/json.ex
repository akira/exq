defmodule Exq.Support.Json do
  def decode(json) do
    Poison.decode(json)
  end

  def encode(e) do
    Poison.encode(e)
  end

  def decode!(json) do
    Poison.decode!(json)
  end

  def encode!(e) do
    Poison.encode!(e)
  end
end