defmodule Exq.Redis.Supervisor do
  use Supervisor

  alias Exq.Support.Config

  @default_timeout 5000

  def start_link(opts) do

    Supervisor.start_link(__MODULE__, [opts], name: __MODULE__)
  end

  def init([opts]) do
  {host, port, database, password, backoff, timeout} = info(opts)
    children = [worker(Redix.Utils, [Redix.Connection, [host: host, port: port],
                                             [backoff: backoff, timeout: timeout]])]
    supervise(children, strategy: :one_for_one, max_restarts: 20)
  end

  def info(opts \\ []) do
    host = Keyword.get(opts, :host, Config.get(:host, '127.0.0.1'))
    port = Keyword.get(opts, :port, Config.get(:port, 6379))
    database = Keyword.get(opts, :database, Config.get(:database, 0))
    password = Keyword.get(opts, :password, Config.get(:password) || '')
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, Config.get(:reconnect_on_sleep, 100))
    timeout = Keyword.get(opts, :redis_timeout, Config.get(:redis_timeout, @default_timeout))
    if is_binary(host), do: host = String.to_char_list(host)
    if is_binary(password), do: password = String.to_char_list(password)
    {host, port, database, password, reconnect_on_sleep, timeout}
  end

end

