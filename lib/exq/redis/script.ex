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
    scheduler_dequeue_jobs:
      Prepare.script("""
      local schedule_queue, namespace_prefix = KEYS[1], KEYS[2]
      local jobs = ARGV
      local dequeued = 0
      for _, job in ipairs(jobs) do
        local job_queue = cjson.decode(job)['queue']
        local count = redis.call('ZREM', schedule_queue, job)
        if count == 1 then
          redis.call('SADD', namespace_prefix .. 'queues', job_queue)
          redis.call('LPUSH', namespace_prefix .. 'queue:' .. job_queue, job)
          dequeued = dequeued + 1
        end
      end
      return dequeued
      """),
    scheduler_dequeue:
      Prepare.script("""
      local schedule_queue = KEYS[1]
      local limit, max_score, namespace_prefix = tonumber(ARGV[1]), tonumber(ARGV[2]), ARGV[3]
      local jobs = redis.call('ZRANGEBYSCORE', schedule_queue, 0, max_score, 'LIMIT', 0, limit)
      for _, job in ipairs(jobs) do
        local job_queue = cjson.decode(job)['queue']
        redis.call('ZREM', schedule_queue, job)
        redis.call('SADD', namespace_prefix .. 'queues', job_queue)
        redis.call('LPUSH', namespace_prefix .. 'queue:' .. job_queue, job)
      end
      return #jobs
      """),
    mlpop_rpush:
      Prepare.script("""
      local from, to = KEYS[1], KEYS[2]
      local limit = tonumber(ARGV[1])
      local length = redis.call('LLEN', from)
      local value = nil
      local moved = 0
      while limit > 0 and length > 0 do
        value = redis.call('LPOP', from)
        redis.call('RPUSH', to, value)
        limit = limit - 1
        length = length - 1
        moved = moved + 1
      end
      return {length, moved}
      """),
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
      local node_id, expected_score, limit = ARGV[1], ARGV[2], tonumber(ARGV[3])
      local node_ids = redis.call('ZRANGEBYSCORE', heartbeat_key, expected_score, expected_score)
      if contains(node_ids, node_id) then
        local length = redis.call('LLEN', backup_queue_key)
        local value = nil
        local moved = 0
        while limit > 0 and length > 0 do
          value = redis.call('LPOP', backup_queue_key)
          redis.call('RPUSH', queue_key, value)
          limit = limit - 1
          length = length - 1
          moved = moved + 1
        end
        return {length, moved}
      else
        return {0, 0}
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
