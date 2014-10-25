defmodule Exq.NamespaceBase do

  def init(opts), do: opts

  def call(conn, _opts) do
    IO.inspect.conn
    conn
  end

  
end