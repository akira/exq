defmodule Exq.Redis do 

  def flushdb!(redis) do 
    {:ok, res} = :eredis.q(redis, [:flushdb])
    res
  end
  
  def smembers!(redis, set) do 
    {:ok, members} = :eredis.q(redis, ["SMEMBERS", set])
    members
  end

  def sadd!(redis, set, member) do 
    {:ok, res} = :eredis.q(redis, ["SADD", set, member])
    res
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
