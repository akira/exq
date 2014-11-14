defmodule Plug.StaticRoot do

  def init(opts), do: opts

  def call(conn, opts) do
    rootify(conn, opts, opts[:to] || "index.html")
  end

  def rootify(%Plug.Conn{path_info: []} = conn, opts, to) do
    %Plug.Conn{conn | path_info: [to]}
    
  end
  def rootify(conn, _opts, _ns), do: conn

end