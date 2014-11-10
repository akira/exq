defmodule Exq.RouterPlug do
  require Logger
  require EEx
  alias Exq.RouterPlug.Router

  def init(options) do
    enq_opts = Keyword.put(options[:exqopts], :name, :exq_enq_ui)
    Exq.Enqueuer.Supervisor.start_link(enq_opts)
    options
  end

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


    get "/api/stats/all" do
      {:ok, processed} = Exq.Api.stats(:exq_enq_ui, "processed")
      {:ok, failed} = Exq.Api.stats(:exq_enq_ui, "failed")
      {:ok, busy} = Exq.Api.busy(:exq_enq_ui)

      {:ok, queues} = Exq.Api.queue_size(:exq_enq_ui)
      qtotal = 0
      queue_sizes = for {q, size} <- queues do
        {size, _} = Integer.parse(size)
        size
      end
      qtotal = "#{Exq.Math.sum_list(queue_sizes)}"

      {:ok, json} = Poison.encode(%{stat: %{id: "all", processed: processed, failed: failed, busy: busy, enqueued: qtotal}})
      send_resp(conn, 200, json)
      conn |> halt
    end

    get "/api/realtimes" do
      {:ok, failures, successes} = Exq.Api.realtime_stats(:exq_enq_ui)

      f = for {date, count} <- failures do
        %{id: "f#{date}", date: date, count: count, type: "failure"}
      end

      s = for {date, count} <- successes do
        %{id: "s#{date}", date: date, count: count, type: "success"}
      end
      all = %{realtimes: f ++ s}
      
      {:ok, json} = Poison.encode(all)
      send_resp(conn, 200, json)
      conn |> halt
    end

    get "/api/failures" do
      {:ok, failed} = Exq.Api.failed(:exq_enq_ui)
      failures = for f <- failed do
        {:ok, fail} = Poison.decode(f, %{})
        Map.put(fail, :id, fail["jid"])
      end
      
      {:ok, json} = Poison.encode(%{failures: failures})

      send_resp(conn, 200, json)
      conn |> halt
    end

    delete "/api/failures/:id" do
      {:ok} = Exq.Api.remove_failed(:exq_enq_ui, id)
      send_resp(conn, 204, "")
      conn |> halt
    end

    delete "/api/failures" do
      {:ok} = Exq.Api.clear_failed(:exq_enq_ui)
      send_resp(conn, 204, "")
      conn |> halt
    end

    post "/api/failures/:id/retry" do
      send_resp(conn, 200, "")
      conn |> halt
    end

    get "/api/processes" do
      {:ok, processes} = Exq.Api.processes(:exq_enq_ui)

      process_jobs = for p <- processes do
        {:ok, process} = Poison.decode(p, %{})
        {:ok, pjob} = Poison.decode(process["job"], %{})
        process = Map.delete(process, "job")
        process = Map.put(process, :job_id, pjob["jid"])
        process = Map.put(process, :id, "#{process["host"]}:#{process["pid"]}")
        pjob = Map.put(pjob, :id, pjob["jid"])
        [process, pjob]
      end

      processes = for [process, job] <- process_jobs, do: process
      jobs = for [process, job] <- process_jobs, do: job

      {:ok, json} = Poison.encode(%{processes: processes, jobs: jobs})
      send_resp(conn, 200, json)
      conn |> halt
    end

    get "/api/queues" do
      {:ok, queues} = Exq.Api.queue_size(:exq_enq_ui)
      job_counts = for {q, size} <- queues, do: %{id: q, size: size}
      {:ok, json} = Poison.encode(%{queues: job_counts})
      send_resp(conn, 200, json)
      conn |> halt
    end

    get "/api/queues/:id" do
      {:ok, jobs} = Exq.Api.jobs(:exq_enq_ui, id)
      jobs_structs = for j <- jobs do
        {:ok, job} = Poison.decode(j, %{})
        Map.put(job, :id, job["jid"])
      end
      job_ids = for j <- jobs_structs, do: j[:id]
      {:ok, json} = Poison.encode(%{queue: %{id: id, job_ids: job_ids, partial: false}, jobs: jobs_structs})
      send_resp(conn, 200, json)
      conn |> halt
    end

    delete "/api/queues/:id" do
      Exq.Api.remove_queue(:exq_enq_ui, id)
      send_resp(conn, 204, "")
      conn |> halt
    end

    # delete "/api/processes/:id" do
    #   {:ok} = Exq.Api.remove_process(:exq_enq_ui, id)
    #   send_resp(conn, 204, "")
    #   conn |> halt
    # end

    delete "/api/processes" do
      {:ok} = Exq.Api.clear_processes(:exq_enq_ui)
      send_resp(conn, 204, "")
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
      send_resp(200, render_index(base: base)) |>
      halt
    end

  end
end