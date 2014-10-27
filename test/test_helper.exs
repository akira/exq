defmodule TestStats do
  def processed_count(redis, namespace) do
    count = Exq.Redis.get!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed"))
    {:ok, count}
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

ExUnit.start
