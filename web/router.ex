defmodule Exq.RouterPlug do
  require Logger
  require EEx
  alias Exq.RouterPlug.Router

  def init(options), do: options

  def call(conn, opts) do
    namespace(conn, opts, opts[:namespace] || "exq")
  end

  def namespace(%Plug.Conn{path_info: [ns | path]} = conn, opts, ns) do
    conn = Plug.Conn.assign(conn, :namespace, opts[:namespace])
    Router.call(%Plug.Conn{conn | path_info: path}, Router.init(opts))
  end
  def namespace(conn, _opts, _ns), do: conn

  defmodule Router do
    import Plug.Conn
    use Plug.Router

    plug Plug.Static, at: "/", from: :exq

    plug :match
    plug :dispatch



    get "/api/queues" do
      Logger.debug "YOLO"
      conn |> halt
    end

    # precompile index.html into render_index/1 function
    index_path = Path.join([Application.app_dir(:exq), "priv/static/index.html"])
    EEx.function_from_file :defp, :render_index, index_path, [:assigns]

    match _ do
      conn |>
      put_resp_header("content-type", "text/html") |>
      send_resp(200, render_index(namespace: "#{conn.assigns[:namespace]}/")) |>
      halt
    end
  end
end