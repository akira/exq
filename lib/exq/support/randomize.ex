defmodule Exq.Support.Randomize do
  @moduledoc """
  Helper functions for random number.
  """

  def random(number) do
    Enum.random(0..number)
  end
end
