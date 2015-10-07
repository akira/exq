defmodule Exq.Redis.Connection do

  alias Exq.Support.Config

  def connection(opts \\ []) do
    {host, port, database, password, reconnect_on_sleep, timeout} = info(opts)
    :eredis.start_link(host, port, database, password, reconnect_on_sleep, timeout)
  end

  def info(opts \\ []) do
    host = Keyword.get(opts, :host, Config.get(:host, '127.0.0.1'))
    port = Keyword.get(opts, :port, Config.get(:port, 6379))
    database = Keyword.get(opts, :database, Config.get(:database, 0))
    password = Keyword.get(opts, :password, Config.get(:password) || '')
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, Config.get(:reconnect_on_sleep, 100))
    timeout = Keyword.get(opts, :redis_timeout, Config.get(:redis_timeout, 5000))
    if is_binary(host), do: host = String.to_char_list(host)
    if is_binary(password), do: password = String.to_char_list(password)
    {host, port, database, password, reconnect_on_sleep, timeout}
  end

  def flushdb!(redis) do
    {:ok, res} = q(redis, [:flushdb])
    res
  end

  def decr!(redis, key) do
    {:ok, count} = q(redis, ["DECR", key])
    count
  end

  def incr!(redis, key) do
    {:ok, count} = q(redis, ["INCR", key])
    count
  end

  def get!(redis, key) do
    {:ok, val} = q(redis, ["GET", key])
    val
  end

  def set!(redis, key, val \\ 0) do
    q(redis, ["SET", key, val])
  end

  def del!(redis, key) do
    q(redis, ["DEL", key])
  end

  def expire!(redis, key, time \\ 10) do
    q(redis, ["EXPIRE", key, time])
  end

  def llen!(redis, list) do
    {:ok, len} = q(redis, ["LLEN", list])
    len
  end

  def keys!(redis, search \\ "*") do
    {:ok, keys} = q(redis, ["KEYS", search])
    keys
  end

  def scan!(redis, cursor, search, count) do
    {:ok, keys} = q(redis, ["SCAN", cursor, "MATCH", search, "COUNT", count])
    keys
  end

  def scard!(redis, set) do
    {:ok, count} = q(redis, ["SCARD", set])
    count
  end

  def smembers!(redis, set) do
    {:ok, members} = q(redis, ["SMEMBERS", set])
    members
  end

  def sadd!(redis, set, member) do
    {:ok, res} = q(redis, ["SADD", set, member])
    res
  end

  def srem!(redis, set, member) do
    {:ok, res} = q(redis, ["SREM", set, member])
    res
  end

  def lrange!(redis, list, range_start \\ "0", range_end \\ "-1") do
    {:ok, items} = q(redis, ["LRANGE", list, range_start, range_end])
    items
  end

  def lrem!(redis, list, value, count \\ 1) do
    {:ok, res} = q(redis, ["LREM", list, count, value])
    res
  end

  def rpush!(redis, key, value) do
    {:ok, res} = q(redis, ["RPUSH", key, value])
    res
  end

  def lpop!(redis, key) do
    case q(redis, ["LPOP", key]) do
      {:ok, :undefined} -> :none
      {:ok, value} -> value
    end
  end

  def zadd!(redis, set, score, member) do
    {:ok, res} = q(redis, ["ZADD", set, score, member])
    res
  end

  def zcard!(redis, set) do
    {:ok, count} = q(redis, ["ZCARD", set])
    count
  end

  def zrangebyscore!(redis, set, min \\ "0", max \\ "+inf") do
    {:ok, items} = q(redis, ["ZRANGEBYSCORE", set, min, max])
    items
  end

  def zrem!(redis, set, member) do
    {:ok, res} = q(redis, ["ZREM", set, member])
    res
  end

  defp q(redis, command) do
    :eredis.q(redis, command, Config.get(:redis_timeout, 5000))
  end
end
