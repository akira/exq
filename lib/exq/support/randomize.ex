defmodule Exq.Support.Randomize do
  def random(number) do
    Enum.random(0..number)
  end
end
