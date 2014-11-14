defmodule Exq.Redis do

  def connection(opts \\ []) do
    host = Keyword.get(opts, :host, Exq.Config.get(:host, '127.0.0.1'))
    port = Keyword.get(opts, :port, Exq.Config.get(:port, 6379))
    database = Keyword.get(opts, :database, Exq.Config.get(:database, 0))
    password = Keyword.get(opts, :password, Exq.Config.get(:password, ''))
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, Exq.Config.get(:reconnect_on_sleep, 100))
    :eredis.start_link(host, port, database, password, reconnect_on_sleep)
  end

  def flushdb!(redis) do
    {:ok, res} = :eredis.q(redis, [:flushdb])
    res
  end

  def decr!(redis, key) do
    {:ok, count} = :eredis.q(redis, ["DECR", key])
    count
  end

  def incr!(redis, key) do
    {:ok, count} = :eredis.q(redis, ["INCR", key])
    count
  end

  def get!(redis, key) do
    {:ok, val} = :eredis.q(redis, ["GET", key])
    val
  end

  def set!(redis, key, val \\ 0) do
    :eredis.q(redis, ["SET", key, val])
  end

  def del!(redis, key) do
    :eredis.q(redis, ["DEL", key])
  end

  def expire!(redis, key, time \\ 10) do
    :eredis.q(redis, ["EXPIRE", key, time])
  end

  def llen!(redis, list) do
    {:ok, len} = :eredis.q(redis, ["LLEN", list])
    len
  end

  def keys!(redis, search \\ "*") do
    {:ok, keys} = :eredis.q(redis, ["KEYS", search])
  end

  def scan!(redis, cursor, search, count) do
    {:ok, keys} = :eredis.q(redis, ["SCAN", cursor, "MATCH", search, "COUNT", count])
  end

  def scard!(redis, set) do
    {:ok, count} = :eredis.q(redis, ["SCARD", set])
    count
  end

  def smembers!(redis, set) do 
    {:ok, members} = :eredis.q(redis, ["SMEMBERS", set])
    members
  end

  def sadd!(redis, set, member) do
    {:ok, res} = :eredis.q(redis, ["SADD", set, member])
    res
  end

  def srem!(redis, set, member) do
    {:ok, res} = :eredis.q(redis, ["SREM", set, member])
    res
  end

  def llen!(redis, list) do
    {:ok, count} = :eredis.q(redis, ["LLEN", list])
    count
  end

  def lrange!(redis, list, range_start \\ "0", range_end \\ "-1") do
    {:ok, items} = :eredis.q(redis, ["LRANGE", list, range_start, range_end])
    items
  end

  def rpush!(redis, key, value) do
    {:ok, res} = :eredis.q(redis, ["RPUSH", key, value])
    res
  end

  def lpop!(redis, key) do
    case :eredis.q(redis, ["LPOP", key]) do
      {:ok, :undefined} -> :none
      {:ok, value} -> value
    end
  end
end
