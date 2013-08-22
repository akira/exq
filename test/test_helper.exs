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
    flush_all
    stop
    Process.unregister(:testredis)
    :ok
  end
end

ExUnit.start
