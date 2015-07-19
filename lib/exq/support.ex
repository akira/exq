defmodule Exq.Support do 
  def take_prefix(full, prefix) do
    base = byte_size(prefix)
    <<_ :: binary-size(base), rest :: binary>> = full
    rest
  end
end
