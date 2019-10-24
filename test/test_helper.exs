defmodule TestStats do
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Support.Coercion
  alias Exq.Support.Config

  def processed_count(redis, namespace) do
    count = Connection.get!(redis, JobQueue.full_key(namespace, "stat:processed"))
    {:ok, count}
  end

  def failed_count(redis, namespace) do
    count = Connection.get!(redis, JobQueue.full_key(namespace, "stat:failed"))
    {:ok, count}
  end
end

defmodule ExqTestUtil do
  @timeout 20
  @long_timeout 100

  alias Exq.Support.Coercion
  alias Exq.Support.Config

  def redis_host do
    Config.get(:host)
  end

  def redis_port do
    :port
    |> Config.get()
    |> Coercion.to_integer()
  end

  import ExUnit.Assertions

  defmodule SendWorker do
    def perform(pid) do
      send(String.to_atom(pid), {:worked})
    end
  end

  def reset_env(previous_env) do
    # Restore all previous values
    System.put_env(previous_env)

    # Remove any newly added keys
    for {key, _} <- System.get_env() do
      unless Map.has_key?(previous_env, key) do
        System.delete_env(key)
      end
    end
  end

  def assert_exq_up(exq) do
    my_pid = String.to_atom(UUID.uuid4())
    Process.register(self(), my_pid)
    {:ok, _} = Exq.enqueue(exq, "default", "ExqTestUtil.SendWorker", [my_pid])
    ExUnit.Assertions.assert_receive({:worked})
    Process.unregister(my_pid)
  end

  def stop_process(pid) do
    try do
      Process.flag(:trap_exit, true)
      Process.exit(pid, :shutdown)

      receive do
        {:EXIT, _pid, _error} -> :ok
      end
    rescue
      e in RuntimeError -> e
    end

    Process.flag(:trap_exit, false)
  end

  def wait do
    :timer.sleep(@timeout)
  end

  def wait_long do
    :timer.sleep(@long_timeout)
  end

  def reset_config do
    config = Mix.Config.read!(Path.join([Path.dirname(__DIR__), "config", "config.exs"]))
    Mix.Config.persist(config)
  end

  def with_application_env(app, key, new, context) do
    old = Application.get_env(app, key)
    Application.put_env(app, key, new)

    try do
      context.()
    after
      Application.put_env(app, key, old)
    end
  end
end

defmodule TestRedis do
  import ExqTestUtil
  alias Exq.Redis.Connection
  alias Exq.Support.Config

  # TODO: Automate config
  def start do
    unless Config.get(:test_with_local_redis) == false do
      [] = :os.cmd('redis-server test/test-redis.conf')
      [] = :os.cmd('redis-server test/test-redis-replica.conf')
      [] = :os.cmd('redis-server test/test-sentinel.conf --sentinel')
      :timer.sleep(500)
    end
  end

  def stop do
    unless Config.get(:test_with_local_redis) == false do
      [] = :os.cmd('redis-cli -p 6555 shutdown')
      [] = :os.cmd('redis-cli -p 6556 shutdown')
      [] = :os.cmd('redis-cli -p 6666 shutdown')
    end
  end

  def setup do
    {:ok, redis} = Redix.start_link(host: redis_host(), port: redis_port())
    Process.register(redis, :testredis)
    flush_all()
    :ok
  end

  def flush_all do
    try do
      Connection.flushdb!(:testredis)
    catch
      :exit, {:timeout, _info} -> nil
    end
  end

  def teardown do
    if !Process.whereis(:testredis) do
      # For some reason at the end of test the link is down, before we actually stop and unregister?
      {:ok, redis} = Redix.start_link(host: redis_host(), port: redis_port())
      Process.register(redis, :testredis)
    end

    try do
      Process.unregister(:testredis)
    rescue
      ArgumentError -> true
    end

    :ok
  end
end

# Don't run parallel tests to prevent redis issues
# Exclude longer running failure condition tests by default
ExUnit.configure(seed: 0, max_cases: 1, exclude: [failure_scenarios: true, pending: true])

# Start logger
for app <- [:logger, :redix, :elixir_uuid] do
  Application.ensure_all_started(app)
end

TestRedis.start()

System.at_exit(fn _status ->
  TestRedis.stop()
end)

ExUnit.start(capture_log: true)
