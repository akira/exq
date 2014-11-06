defmodule TestStats do
  def processed_count(redis, namespace) do
    count = Exq.Redis.get!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed"))
    {:ok, count}
  end

  def failed_count(redis, namespace) do
    count = Exq.Redis.get!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed"))
    {:ok, count}
  end
end

defmodule ExqTestUtil do
  @timeout 20
  @long_timeout 100

  import ExUnit.Assertions

  defmodule SendWorker do
    def perform(pid) do
      send String.to_atom(pid), {:worked}
    end
  end

  def assert_exq_up(exq) do
    my_pid = String.to_atom(UUID.uuid4)
    Process.register(self, my_pid)
    {:ok, jid} = Exq.enqueue(exq, "default", "ExqTestUtil.SendWorker", [my_pid])
    wait_long
    ExUnit.Assertions.assert_received {:worked}
    Process.unregister(my_pid)
  end

  def wait do
    :timer.sleep(@timeout)
  end

  def wait_long do
    :timer.sleep(@long_timeout)
  end

end

defmodule TestRedis do
  #TODO: Automate config
  def start do
    [] = :os.cmd('redis-server test/test-redis.conf')
    :timer.sleep(100)
  end

  def stop do
    [] = :os.cmd('redis-cli -p 6555 shutdown')
  end

  def setup do
    start
    {:ok, redis} = :eredis.start_link('127.0.0.1', 6555)
    Process.register(redis, :testredis)
    :ok
  end

  def flush_all do
      Exq.Redis.flushdb! :testredis
  end

  def teardown do
    if !Process.whereis(:testredis) do
      # For some reason at the end of test the link is down, before we acutally stop and unregister?
      {:ok, redis} = :eredis.start_link('127.0.0.1', 6555)
      Process.register(redis, :testredis)
    end
    flush_all
    stop
    Process.unregister(:testredis)
    :ok
  end
end

# Don't run parallel tests to prevent redis issues
ExUnit.configure(seed: 0, max_cases: 1)

ExUnit.start
