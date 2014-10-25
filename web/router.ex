defmodule Exq.RouterPlug do
  require Logger
  require EEx
  alias Exq.RouterPlug.Router

  def init(options), do: options

  def call(conn, opts) do
    case opts[:namespace] do
      "" ->
        Router.call(Plug.Conn.assign(conn, :namespace, ""), Router.init(opts))
      _ ->
        namespace(conn, opts, opts[:namespace] || "exq")
    end
  end

  def namespace(%Plug.Conn{path_info: [ns | path]} = conn, opts, ns) do
    Router.call(%Plug.Conn{Plug.Conn.assign(conn, :namespace, ns) | path_info: path}, Router.init(opts))
  end
  def namespace(conn, _opts, _ns), do: conn

  defmodule Router do
    import Plug.Conn
    use Plug.Router

    plug Plug.Static, at: "/", from: :exq
    plug JsonApi, on: "api"

    plug :match
    plug :dispatch



    get "/api/queues" do
      Exq.enqueue(:exq, "default", "TestWorker", [])
      Exq.enqueue(:exq, "default", "TestWorker", [])
      {:ok, queues} = Exq.queue_size(:exq)
      job_counts = for {q, size} <- queues, do: %{id: q, size: size}
      {:ok, json} = JSEX.encode(%{queues: job_counts})
      send_resp(conn, 200, json)
      conn |> halt
    end

    get "/api/queues/:id" do
      {:ok, jobs} = Exq.jobs(:exq, id)
      jobs_structs = for {j, id} <- Enum.with_index(jobs), do: %{id: id, job: j}
      job_ids = for {j, id} <- Enum.with_index(jobs), do: id
      {:ok, json} = JSEX.encode(%{queue: %{id: id, job_ids: job_ids}, jobs: jobs_structs})
      send_resp(conn, 200, json)
      conn |> halt
    end


    

    # precompile index.html into render_index/1 function
    index_path = Path.join([Application.app_dir(:exq), "priv/static/index.html"])
    EEx.function_from_file :defp, :render_index, index_path, [:assigns]

    match _ do
      base = "" 
      if conn.assigns[:namespace] != "" do
        base = "#{conn.assigns[:namespace]}/"
      end

      conn |>
      put_resp_header("content-type", "text/html") |>
      send_resp(200, render_index(namespace: "#{conn.assigns[:namespace]}/", base: base)) |>
      halt
    end

  end
end