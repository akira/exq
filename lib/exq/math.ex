defmodule Exq.Math do 
  def sum_list([]) do
    0
  end
  def sum_list([h|t]) do
    h + sum_list(t)
  end
end
