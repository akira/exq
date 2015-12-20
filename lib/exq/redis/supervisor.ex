defmodule Exq.Redis.Supervisor do
  use Supervisor

  alias Exq.Support.Config

  @default_timeout 5000

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [opts], name: supervisor_name(opts[:name]))
  end

  def init([opts]) do
    {redix_opts, connection_opts} = info(opts)
    children = [
      worker(Redix, [redix_opts, connection_opts])
      ]
    supervise(children, strategy: :one_for_one)
  end

  def info(opts \\ []) do
    host = Keyword.get(opts, :host, Config.get(:host, '127.0.0.1'))
    port = Keyword.get(opts, :port, Config.get(:port, 6379))
    database = Keyword.get(opts, :database, Config.get(:database, 0))
    password = Keyword.get(opts, :password, Config.get(:password))
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, Config.get(:reconnect_on_sleep, 100))
    timeout = Keyword.get(opts, :redis_timeout, Config.get(:redis_timeout, @default_timeout))
    if is_binary(host), do: host = String.to_char_list(host)
    {[host: host, port: port, database: database, password: password],
     [backoff: reconnect_on_sleep, timeout: timeout, name: client_name(opts[:name])]}
  end

  def client_name(nil), do: Exq.Redis.Client
  def client_name(name), do: "#{name}.Redis.Client" |> String.to_atom

  def supervisor_name(nil), do: Exq.Redis.Sup
  def supervisor_name(name), do: "#{name}.Redis.Sup" |> String.to_atom

end

