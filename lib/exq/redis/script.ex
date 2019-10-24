defmodule Exq.Redis.Script do
  alias Exq.Redis.Connection

  defmodule Prepare do
    def script(source) do
      hash =
        :crypto.hash(:sha, source)
        |> Base.encode16(case: :lower)

      {hash, source}
    end
  end

  @scripts %{
    heartbeat_re_enqueue_backup:
      Prepare.script("""
      local function contains(table, element)
        for _, value in pairs(table) do
          if value == element then
            return true
          end
        end
        return false
      end

      local backup_queue_key, queue_key, heartbeat_key = KEYS[1], KEYS[2], KEYS[3]
      local node_id, expected_score = ARGV[1], ARGV[2]
      local node_ids = redis.call('ZRANGEBYSCORE', heartbeat_key, expected_score, expected_score)
      if contains(node_ids, node_id) then
        return redis.call('RPOPLPUSH', backup_queue_key, queue_key)
      else
        return nil
      end
      """)
  }

  def eval!(redis, script, keys, args) do
    {hash, source} = @scripts[script]

    case Connection.q(redis, ["EVALSHA", hash, length(keys)] ++ keys ++ args) do
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} ->
        Connection.q(redis, ["EVAL", source, length(keys)] ++ keys ++ args)

      result ->
        result
    end
  end
end
