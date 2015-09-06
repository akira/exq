defmodule Exq.RouterPlug do
  require Logger
  require EEx
  alias Exq.RouterPlug.Router

  def init(options) do
    if options[:exqopts] do
      enq_opts = options[:exqopts]
    else
      enq_opts = [{:name, :exq_enqueuer}]
    end
    Keyword.put(options, :exqopts, enq_opts)
  end

  def call(conn, opts) do
    namespace_opt = opts[:namespace] || "exq"
    conn = Plug.Conn.assign(conn, :namespace, namespace_opt)
    conn = Plug.Conn.assign(conn, :exq_name, opts[:exqopts][:name])
    case namespace_opt do
      "" ->
        Router.call(conn, Router.init(opts))
      _ ->
        namespace(conn, opts, namespace_opt)
    end
  end

  def namespace(%Plug.Conn{path_info: [ns | path]} = conn, opts, ns) do
    Router.call(%Plug.Conn{conn | path_info: path}, Router.init(opts))
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
      {:ok, processed} = Exq.Api.stats(conn.assigns[:exq_name], "processed")
      {:ok, failed} = Exq.Api.stats(conn.assigns[:exq_name], "failed")
      {:ok, busy} = Exq.Api.busy(conn.assigns[:exq_name])
      {:ok, scheduled} = Exq.Api.queue_size(conn.assigns[:exq_name], :scheduled)

      {:ok, queues} = Exq.Api.queue_size(conn.assigns[:exq_name])
      queue_sizes = for {_q, size} <- queues do
        {size, _} = Integer.parse(size)
        size
      end
      qtotal = "#{Enum.sum(queue_sizes)}"

      {:ok, json} = Poison.encode(%{stat: %{id: "all", processed: processed, failed: failed, busy: busy, scheduled: scheduled, enqueued: qtotal}})
      conn |> send_resp(200, json) |> halt
    end

    get "/api/realtimes" do
      {:ok, failures, successes} = Exq.Api.realtime_stats(conn.assigns[:exq_name])

      f = for {date, count} <- failures do
        %{id: "f#{date}", date: date, count: count, type: "failure"}
      end

      s = for {date, count} <- successes do
        %{id: "s#{date}", date: date, count: count, type: "success"}
      end
      all = %{realtimes: f ++ s}

      {:ok, json} = Poison.encode(all)
      conn |> send_resp(200, json) |> halt
    end

    get "/api/failures" do
      {:ok, failed} = Exq.Api.failed(conn.assigns[:exq_name])
      failures = for f <- failed do
        {:ok, fail} = Poison.decode(f, %{})
        Map.put(fail, :id, fail["jid"])
      end

      {:ok, json} = Poison.encode(%{failures: failures})
      conn |> send_resp(200, json) |> halt
    end

    delete "/api/failures/:id" do
      {:ok} = Exq.Api.remove_failed(conn.assigns[:exq_name], id)
      conn |> send_resp(204, "") |> halt
    end

    delete "/api/failures" do
      {:ok} = Exq.Api.clear_failed(conn.assigns[:exq_name])
      conn |> send_resp(204, "") |> halt
    end

    post "/api/failures/:id/retry" do
      conn |> send_resp(200, "") |> halt
    end

    get "/api/processes" do
      {:ok, processes} = Exq.Api.processes(conn.assigns[:exq_name])

      process_jobs = for p <- processes do
        {:ok, process} = Poison.decode(p, %{})
        {:ok, pjob} = Poison.decode(process["job"], %{})
        process = Map.delete(process, "job")
        process = Map.put(process, :job_id, pjob["jid"])
        process = Map.put(process, :id, "#{process["host"]}:#{process["pid"]}")
        pjob = Map.put(pjob, :id, pjob["jid"])
        [process, pjob]
      end

      processes = for [process, _job] <- process_jobs, do: process
      jobs = for [_process, job] <- process_jobs, do: job

      {:ok, json} = Poison.encode(%{processes: processes, jobs: jobs})
      conn |> send_resp(200, json) |> halt
    end

    get "/api/queues" do
      {:ok, queues} = Exq.Api.queue_size(conn.assigns[:exq_name])
      job_counts = for {q, size} <- queues, do: %{id: q, size: size}
      {:ok, json} = Poison.encode(%{queues: job_counts})
      conn |> send_resp(200, json) |> halt
    end

    get "/api/queues/:id" do
      {:ok, jobs} = Exq.Api.jobs(conn.assigns[:exq_name], id)
      jobs_structs = for j <- jobs do
        {:ok, job} = Poison.decode(j, %{})
        Map.put(job, :id, job["jid"])
      end
      job_ids = for j <- jobs_structs, do: j[:id]
      {:ok, json} = Poison.encode(%{queue: %{id: id, job_ids: job_ids, partial: false}, jobs: jobs_structs})
      conn |> send_resp(200, json) |> halt
    end

    delete "/api/queues/:id" do
      Exq.Api.remove_queue(conn.assigns[:exq_name], id)
      conn |> send_resp(204, "") |> halt
    end

    # delete "/api/processes/:id" do
    #   {:ok} = Exq.Api.remove_process(:exq_enq_ui, id)
    #   conn |> send_resp(204, "") |> halt
    # end

    delete "/api/processes" do
      {:ok} = Exq.Api.clear_processes(conn.assigns[:exq_name])
      conn |> send_resp(204, "") |> halt
    end



    # precompile index.html into render_index/1 function
    index_path = Path.join([Application.app_dir(:exq), "priv/static/index.html"])
    EEx.function_from_file :defp, :render_index, index_path, [:assigns]

    match _ do
      base = ""
      if conn.assigns[:namespace] != "" do
        base = "#{conn.assigns[:namespace]}/"
      end

      conn
        |> put_resp_header("content-type", "text/html")
        |> send_resp(200, render_index(base: base))
        |> halt
    end

  end
end
