defmodule Exq.Redis.Script do
  alias Exq.Redis.Connection

  defmodule Prepare do
    def script(source) do
      hash = :crypto.hash(:sha, source)
                    |> Base.encode16(case: :lower)

      {hash, source}
    end
  end

  @scripts %{
    schedule: Prepare.script("""
      local schedule_queue_key, job_queue_key = KEYS[1], KEYS[2]
      local jid, score, job_serialized = ARGV[1], ARGV[2], ARGV[3]

      redis.call('ZADD', schedule_queue_key, score, jid)
      redis.call('HSET', schedule_queue_key .. ':job', jid, job_serialized)
      redis.call('HSET', schedule_queue_key .. ':job_queue', jid, job_queue_key)
      """),
    schedule_dequeue: Prepare.script("""
      local schedule_queue_key, queues_key = KEYS[1], KEYS[2]
      local score, page_size = ARGV[1], ARGV[2]

      local dequeue_count = 0
      for i, jid in ipairs(redis.call('ZRANGEBYSCORE', schedule_queue_key, 0, score, 'LIMIT', 0, page_size)) do
        local job_serialized = redis.call('HGET', schedule_queue_key .. ':job', jid)
        local job_queue_key = redis.call('HGET', schedule_queue_key .. ':job_queue', jid)

        redis.call('SADD', 'queues', queues_key, job_queue_key)
        redis.call('LPUSH', job_queue_key, job_serialized)

        redis.call('ZREM', schedule_queue_key, jid)
        redis.call('HDEL', schedule_queue_key .. ':job', jid)
        redis.call('HDEL', schedule_queue_key .. ':job_queue', jid)

        dequeue_count = dequeue_count + 1
      end

      return dequeue_count
      """),
    schedule_jobs_with_scores: Prepare.script("""
      local schedule_queue_key = KEYS[1]

      local jobs_with_scores = {}
      for i, jid_or_score in ipairs(redis.call('ZRANGEBYSCORE', schedule_queue_key, 0, '+inf', 'WITHSCORES')) do
        if i % 2 == 0 then
          redis.call("SET", "score", jid_or_score)
          table.insert(jobs_with_scores, jid_or_score)
        else
          redis.call("SET", "jid", jid_or_score)
          table.insert(jobs_with_scores, redis.call('HGET', schedule_queue_key .. ':job', jid_or_score))
        end
      end

      return jobs_with_scores
      """)
  }

  def eval!(redis, script, keys, args) do
    {hash, source} = @scripts[script]

    {:ok, res} = try do
      Connection.q(redis, ["EVALSHA", hash, length(keys)] ++ keys ++ args)
    rescue e in Redix.Error ->
      stacktrace = System.stacktrace

      case String.split(e.message, " ", parts: 2) do
        ["NOSCRIPT", _] ->
          Connection.q(redis, ["EVAL", source, length(keys)] ++ keys ++ args)
        _ ->
          reraise e, stacktrace
      end
    end

    res
  end
end
