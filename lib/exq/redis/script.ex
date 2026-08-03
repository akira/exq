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
    compare_and_delete:
      Prepare.script("""
      local key = KEYS[1]
      local expected_value = ARGV[1]
      local current_value = redis.call("get", key)
      if current_value == expected_value then
        return redis.call("del", key)
      else
        return 0
      end
      """),
    clear_serial:
      Prepare.script("""
      local unique_key = KEYS[1]
      local started_key = unique_key .. ':started'
      local pending_key = unique_key .. ':pending'
      local jid = ARGV[1]

      if redis.call('GET', unique_key) ~= jid then
        return 0
      end

      redis.call('DEL', unique_key)
      if redis.call('GET', started_key) == jid then
        redis.call('DEL', started_key)
      end

      local pending = redis.call('GET', pending_key)
      if pending and cjson.decode(pending)['parent_jid'] == jid then
        redis.call('DEL', pending_key)
      end

      return 1
      """),
    enqueue:
      Prepare.script("""
      local queues_key, job_queue_key, unique_key = KEYS[1], KEYS[2], KEYS[3]
      local job_queue, job, jid, unlocks_in, serial = ARGV[1], ARGV[2], ARGV[3], tonumber(ARGV[4]), tonumber(ARGV[5]) == 1
      local unlocked = true
      local conflict_jid = nil

      if unlocks_in then
        unlocked = redis.call("set", unique_key, jid, "px", unlocks_in, "nx")
      end

      if unlocked then
        if serial then
          redis.call('DEL', unique_key .. ':started')
          redis.call('DEL', unique_key .. ':pending')
        end

        redis.call('SADD', queues_key, job_queue)
        redis.call('LPUSH', job_queue_key, job)
        return 0
      else
        conflict_jid = redis.call("get", unique_key)
      end

      if not serial or not conflict_jid then
        return {1, conflict_jid}
      end

      local active_jid = conflict_jid

      local started_key = unique_key .. ':started'
      if redis.call('GET', started_key) ~= active_jid then
        return {1, active_jid}
      end

      local pending_key = unique_key .. ':pending'
      local pending = redis.call('GET', pending_key)
      if pending then
        local pending_job = cjson.decode(pending)
        if pending_job['parent_jid'] == active_jid then
          return {1, pending_job['jid']}
        end

        redis.call('DEL', pending_key)
      end

      local ttl = redis.call('PTTL', unique_key)
      if ttl <= 0 then
        return {1, active_jid}
      end

      local pending_job = cjson.encode({parent_jid = active_jid, jid = jid, job = job, score = 0})
      redis.call('PSETEX', pending_key, ttl, pending_job)

      return {2, jid}
      """),
    enqueue_at:
      Prepare.script("""
      local schedule_queue, unique_key = KEYS[1], KEYS[2]
      local job, score, jid, unlocks_in, serial = ARGV[1], tonumber(ARGV[2]), ARGV[3], tonumber(ARGV[4]), tonumber(ARGV[5]) == 1
      local unlocked = true
      local conflict_jid = nil

      if unlocks_in then
        unlocked = redis.call("set", unique_key, jid, "px", unlocks_in, "nx")
      end

      if unlocked then
        if serial then
          redis.call('DEL', unique_key .. ':started')
          redis.call('DEL', unique_key .. ':pending')
        end

        redis.call('ZADD', schedule_queue, score, job)
        return 0
      else
        conflict_jid = redis.call("get", unique_key)
      end

      if not serial or not conflict_jid then
        return {1, conflict_jid}
      end

      local active_jid = conflict_jid

      local started_key = unique_key .. ':started'
      if redis.call('GET', started_key) ~= active_jid then
        return {1, active_jid}
      end

      local pending_key = unique_key .. ':pending'
      local pending = redis.call('GET', pending_key)
      if pending then
        local pending_job = cjson.decode(pending)
        if pending_job['parent_jid'] == active_jid then
          return {1, pending_job['jid']}
        end

        redis.call('DEL', pending_key)
      end

      local ttl = redis.call('PTTL', unique_key)
      if ttl <= 0 then
        return {1, active_jid}
      end

      local pending_job = cjson.encode({parent_jid = active_jid, jid = jid, job = job, score = score})
      redis.call('PSETEX', pending_key, ttl, pending_job)

      return {2, jid}
      """),
    mark_serial_started:
      Prepare.script("""
      local unique_key = KEYS[1]
      local started_key = unique_key .. ':started'
      local jid = ARGV[1]

      if redis.call('GET', unique_key) ~= jid then
        return 0
      end

      local ttl = redis.call('PTTL', unique_key)
      if ttl <= 0 then
        return 0
      end

      redis.call('PSETEX', started_key, ttl, jid)
      return 1
      """),
    complete_serial:
      Prepare.script("""
      local queues_key, schedule_queue = KEYS[1], KEYS[2]
      local unique_key = KEYS[3]
      local started_key = unique_key .. ':started'
      local pending_key = unique_key .. ':pending'
      local completed_jid, namespace_prefix, now = ARGV[1], ARGV[2], tonumber(ARGV[3])

      if redis.call('GET', unique_key) ~= completed_jid then
        return 0
      end

      local pending = redis.call('GET', pending_key)
      if not pending then
        redis.call('DEL', unique_key)
        if redis.call('GET', started_key) == completed_jid then
          redis.call('DEL', started_key)
        end
        return 0
      end

      local pending_job = cjson.decode(pending)
      if pending_job['parent_jid'] ~= completed_jid then
        redis.call('DEL', unique_key)
        redis.call('DEL', pending_key)
        if redis.call('GET', started_key) == completed_jid then
          redis.call('DEL', started_key)
        end
        return 0
      end

      local job = cjson.decode(pending_job['job'])
      local unique_for = tonumber(job['unique_for'])
      if not unique_for or unique_for <= 0 then
        return 0
      end

      local ttl = unique_for * 1000
      if pending_job['score'] > now then
        ttl = ttl + (pending_job['score'] - now) * 1000
      end

      redis.call('SET', unique_key, pending_job['jid'], 'PX', math.floor(ttl))
      redis.call('DEL', pending_key)
      if redis.call('GET', started_key) == completed_jid then
        redis.call('DEL', started_key)
      end

      if pending_job['score'] == 0 then
        redis.call('SADD', queues_key, job['queue'])
        redis.call('LPUSH', namespace_prefix .. 'queue:' .. job['queue'], pending_job['job'])
      else
        redis.call('ZADD', schedule_queue, pending_job['score'], pending_job['job'])
      end

      return 1
      """),
    enqueue_all:
      Prepare.script("""
      local schedule_queue, queues_key = KEYS[1], KEYS[2]
      local i = 1
      local result = {}

      while i <= #(ARGV) / 5 do
        local keys_start = i * 2
        local args_start = (i - 1) * 5
        local unique_key, job_queue_key = KEYS[keys_start + 1], KEYS[keys_start + 2]
        local started_key = unique_key .. ':started'
        local pending_key = unique_key .. ':pending'
        local jid        = ARGV[args_start + 1]
        local job_queue  = ARGV[args_start + 2]
        local score      = tonumber(ARGV[args_start + 3])
        local job        = ARGV[args_start + 4]
        local unlocks_in = tonumber(ARGV[args_start + 5])
        local unlocked   = true
        local conflict_jid = nil
        local serial = false

        if unlocks_in then
          unlocked = redis.call("set", unique_key, jid, "px", unlocks_in, "nx")
          serial = cjson.decode(job)['unique_until'] == 'serial'
        end

        if unlocked then
          if serial then
            redis.call('DEL', started_key)
            redis.call('DEL', pending_key)
          end

          if score == 0 then
            redis.call('SADD', queues_key, job_queue)
            redis.call('LPUSH', job_queue_key, job)
          else
            redis.call('ZADD', schedule_queue, score, job)
          end
          result[i] = {0, jid}
        else
          conflict_jid = redis.call("get", unique_key)

          if serial and conflict_jid and redis.call('GET', started_key) == conflict_jid then
            local pending = redis.call('GET', pending_key)

            if pending then
              local pending_job = cjson.decode(pending)
              if pending_job['parent_jid'] == conflict_jid then
                result[i] = {1, pending_job['jid']}
              else
                redis.call('DEL', pending_key)
              end
            end

            if not result[i] then
              local ttl = redis.call('PTTL', unique_key)
              if ttl > 0 then
                local pending_job = cjson.encode({parent_jid = conflict_jid, jid = jid, job = job, score = score})
                redis.call('PSETEX', pending_key, ttl, pending_job)
                result[i] = {2, jid}
              else
                result[i] = {1, conflict_jid}
              end
            end
          else
            result[i] = {1, conflict_jid}
          end
        end

        i = i + 1
      end

      return result
      """),
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
