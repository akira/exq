defmodule Exq.Redis.JobQueue do
  @moduledoc """
  The JobQueue module is the main abstraction of a job queue on top of Redis.

  It provides functionality for:
    * Storing jobs in Redis
    * Fetching the next job(s) to be executed (and storing a backup of these).
    * Scheduling future jobs in Redis
    * Fetching scheduling jobs and moving them to current job list
    * Retrying or failing a job
    * Re-hydrating jobs from a backup queue

  """

  require Logger

  alias Exq.Redis.Connection
  alias Exq.Redis.Script
  alias Exq.Support.Job
  alias Exq.Support.Config
  alias Exq.Support.Time

  @default_size 100

  def enqueue(redis, namespace, queue, worker, args, options) do
    {jid, job, job_serialized} = to_job_serialized(queue, worker, args, options)

    case do_enqueue(redis, namespace, queue, job, job_serialized, unique_check: true) do
      :ok -> {:ok, jid}
      other -> other
    end
  end

  defp do_enqueue(redis, namespace, queue, job, job_serialized, options \\ []) do
    try do
      [unlocks_in, unique_key] = unique_args(namespace, job, options)

      keys = keys_list([full_key(namespace, "queues"), queue_key(namespace, queue)], unique_key)

      response =
        Script.eval!(
          redis,
          :enqueue,
          keys,
          [queue, job_serialized, job.jid, unlocks_in]
        )

      case response do
        {:ok, 0} -> :ok
        {:ok, [1, old_jid]} -> {:conflict, old_jid}
        error -> error
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect(e)}")
        {:error, :timeout}
    end
  end

  def unlock_jobs(redis, namespace, raw_jobs) do
    for raw_job <- raw_jobs,
        job = Job.decode(raw_job),
        unique_token = job.unique_token do
      unlock(redis, namespace, unique_token, job.jid)
    end
  end

  def unlock(redis, namespace, unique_token, jid) do
    Exq.Support.Redis.with_retry_on_connection_error(
      fn ->
        Script.eval!(
          redis,
          :compare_and_delete,
          [unique_key(namespace, unique_token)],
          [jid]
        )
      end,
      3
    )
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args, options)
      when is_integer(offset) do
    time = Time.offset_from_now(offset)
    enqueue_at(redis, namespace, queue, time, worker, args, options)
  end

  def enqueue_at(redis, namespace, queue, time, worker, args, options) do
    {jid, job, job_serialized} =
      to_job_serialized(queue, worker, args, options, Time.unix_seconds(time))

    do_enqueue_job_at(
      redis,
      namespace,
      job,
      job_serialized,
      jid,
      time,
      scheduled_queue_key(namespace),
      unique_check: true
    )
  end

  def do_enqueue_job_at(
        redis,
        namespace,
        job,
        job_serialized,
        jid,
        time,
        scheduled_queue,
        options \\ []
      ) do
    score = Time.time_to_score(time)

    try do
      [unlocks_in, unique_key] = unique_args(namespace, job, options)

      keys = keys_list([scheduled_queue], unique_key)

      response =
        Script.eval!(redis, :enqueue_at, keys, [
          job_serialized,
          score,
          jid,
          unlocks_in
        ])

      case response do
        {:ok, 0} -> {:ok, jid}
        {:ok, [1, old_jid]} -> {:conflict, old_jid}
        error -> error
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect(e)}")
        {:error, :timeout}
    end
  end

  def enqueue_all(redis, namespace, jobs) do
    {keys, args} = extract_enqueue_all_keys_and_args(namespace, jobs)

    try do
      response =
        Script.eval!(
          redis,
          :enqueue_all,
          [scheduled_queue_key(namespace), full_key(namespace, "queues")] ++ keys,
          args
        )

      case response do
        {:ok, result} ->
          {
            :ok,
            Enum.map(result, fn [status, jid] ->
              case status do
                0 -> {:ok, jid}
                1 -> {:conflict, jid}
              end
            end)
          }

        error ->
          error
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect(e)}")
        {:error, :timeout}
    end
  end

  @doc """
  Dequeue jobs for available queues
  """
  def dequeue(redis, namespace, node_id, queues) when is_list(queues) do
    dequeue_multiple(redis, namespace, node_id, queues)
  end

  defp dequeue_multiple(_redis, _namespace, _node_id, []) do
    {:ok, {:none, nil}}
  end

  defp dequeue_multiple(redis, namespace, node_id, queues) do
    deq_commands =
      Enum.map(queues, fn queue ->
        ["RPOPLPUSH", queue_key(namespace, queue), backup_queue_key(namespace, node_id, queue)]
      end)

    resp = Connection.qp(redis, deq_commands)

    case resp do
      {:error, reason} ->
        [{:error, reason}]

      {:ok, success} ->
        success
        |> Enum.zip(queues)
        |> Enum.map(fn {resp, queue} ->
          case resp do
            :undefined -> {:ok, {:none, queue}}
            nil -> {:ok, {:none, queue}}
            %Redix.Error{} = error -> {:error, {error, queue}}
            value -> {:ok, {value, queue}}
          end
        end)
    end
  end

  def re_enqueue_backup(redis, namespace, node_id, queue) do
    resp =
      Script.eval!(
        redis,
        :mlpop_rpush,
        [backup_queue_key(namespace, node_id, queue), queue_key(namespace, queue)],
        [10]
      )

    case resp do
      {:ok, [remaining, moved]} ->
        if moved > 0 do
          Logger.info(
            "Re-enqueued #{moved} job(s) from backup for node_id [#{node_id}] and queue [#{queue}]"
          )
        end

        if remaining > 0 do
          re_enqueue_backup(redis, namespace, node_id, queue)
        end

      _ ->
        nil
    end
  end

  def remove_job_from_backup(redis, namespace, node_id, queue, job_serialized) do
    Connection.lrem!(redis, backup_queue_key(namespace, node_id, queue), job_serialized, 1,
      retry_on_connection_error: 3
    )
  end

  def scheduler_dequeue(redis, namespace) do
    scheduler_dequeue(redis, namespace, Time.time_to_score())
  end

  def scheduler_dequeue(redis, namespace, max_score) do
    schedule_queues(namespace)
    |> Enum.map(
      &do_scheduler_dequeue(redis, namespace, &1, max_score, Config.get(:scheduler_page_size), 0)
    )
    |> Enum.sum()
  end

  defp do_scheduler_dequeue(redis, namespace, queue, max_score, limit, acc) do
    case Script.eval!(redis, :scheduler_dequeue, [queue], [
           limit,
           max_score,
           full_key(namespace, "")
         ]) do
      {:ok, count} ->
        if count == limit do
          do_scheduler_dequeue(redis, namespace, queue, max_score, limit, count + acc)
        else
          count + acc
        end

      {:error, reason} ->
        Logger.warning(
          "Error dequeueing jobs from scheduler queue #{queue} - #{Kernel.inspect(reason)}"
        )

        0
    end
  end

  defp keys_list([_hd | _tl] = keys, nil), do: keys
  defp keys_list([_hd | _tl] = keys, key), do: keys ++ [key]

  def full_key("", key), do: key
  def full_key(nil, key), do: key

  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  def unique_key(namespace, unique_token) do
    full_key(namespace, "unique:#{unique_token}")
  end

  def backup_queue_key(namespace, node_id, queue) do
    full_key(namespace, "queue:backup::#{node_id}::#{queue}")
  end

  def schedule_queues(namespace) do
    [scheduled_queue_key(namespace), retry_queue_key(namespace)]
  end

  def scheduled_queue_key(namespace) do
    full_key(namespace, "schedule")
  end

  def retry_queue_key(namespace) do
    full_key(namespace, "retry")
  end

  def failed_queue_key(namespace) do
    full_key(namespace, "dead")
  end

  def dead?(job) do
    retry_count = (job.retry_count || 0) + 1

    case job do
      %{retry: retry} when is_integer(retry) and retry > 0 ->
        retry_count > retry

      %{retry: true} ->
        retry_count > get_max_retries()

      _ ->
        true
    end
  end

  def snooze_job(redis, namespace, job, offset) do
    job =
      %{job | error_message: "Snoozed for #{offset} seconds"}
      |> add_failure_timestamp()

    time = Time.offset_from_now(offset)
    Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")

    {:ok, _jid} =
      do_enqueue_job_at(
        redis,
        namespace,
        job,
        Job.encode(job),
        job.jid,
        time,
        retry_queue_key(namespace)
      )
  end

  def retry_or_fail_job(redis, namespace, job, error) do
    if dead?(job) do
      Logger.info("Max retries on job #{job.jid} exceeded")
      fail_job(redis, namespace, job, error)
    else
      retry_count = (job.retry_count || 0) + 1
      retry_job(redis, namespace, job, retry_count, error)
    end
  end

  def retry_job(redis, namespace, job, retry_count, error) do
    job =
      %{job | retry_count: retry_count, error_message: error}
      |> add_failure_timestamp()

    offset = Config.backoff().offset(job)
    time = Time.offset_from_now(offset)
    Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")

    {:ok, _jid} =
      do_enqueue_job_at(
        redis,
        namespace,
        job,
        Job.encode(job),
        job.jid,
        time,
        retry_queue_key(namespace)
      )
  end

  def retry_job(redis, namespace, job) do
    remove_retry(redis, namespace, job.jid)
    :ok = do_enqueue(redis, namespace, job.queue, job, Job.encode(job))
  end

  def fail_job(redis, namespace, job, error) do
    job =
      %{
        job
        | retry_count: job.retry_count || 0,
          error_class: "ExqGenericError",
          error_message: error
      }
      |> add_failure_timestamp()

    job_serialized = Job.encode(job)
    key = failed_queue_key(namespace)

    now = Time.unix_seconds()

    commands = [
      ["ZADD", key, Time.time_to_score(), job_serialized],
      ["ZREMRANGEBYSCORE", key, "-inf", now - Config.get(:dead_timeout_in_seconds)],
      ["ZREMRANGEBYRANK", key, 0, -Config.get(:dead_max_jobs) - 1]
    ]

    Connection.qp!(redis, commands, retry_on_connection_error: 3)
  end

  def queue_size(redis, namespace) do
    queues = list_queues(redis, namespace)
    for q <- queues, do: {q, queue_size(redis, namespace, q)}
  end

  def queue_size(redis, namespace, :scheduled) do
    Connection.zcard!(redis, scheduled_queue_key(namespace))
  end

  def queue_size(redis, namespace, :retry) do
    Connection.zcard!(redis, retry_queue_key(namespace))
  end

  def queue_size(redis, namespace, queue) do
    Connection.llen!(redis, queue_key(namespace, queue))
  end

  def delete_queue(redis, namespace, queue) do
    Connection.del!(redis, full_key(namespace, queue))
  end

  def jobs(redis, namespace) do
    queues = list_queues(redis, namespace)
    for q <- queues, do: {q, jobs(redis, namespace, q)}
  end

  def jobs(redis, namespace, queue, options \\ []) do
    range_start = Keyword.get(options, :offset, 0)
    range_end = range_start + Keyword.get(options, :size, @default_size) - 1

    Connection.lrange!(redis, queue_key(namespace, queue), range_start, range_end)
    |> maybe_decode(options)
  end

  def scheduled_jobs(redis, namespace, queue, options \\ []) do
    if Keyword.get(options, :score, false) do
      scheduled_jobs_with_scores(redis, namespace, queue, options)
    else
      Connection.zrangebyscorewithlimit!(
        redis,
        full_key(namespace, queue),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> maybe_decode(options)
    end
  end

  def scheduled_jobs_with_scores(redis, namespace, queue, options \\ []) do
    Connection.zrangebyscorewithscoreandlimit!(
      redis,
      full_key(namespace, queue),
      Keyword.get(options, :offset, 0),
      Keyword.get(options, :size, @default_size)
    )
    |> decode_zset_withscores(options)
  end

  def failed(redis, namespace, options \\ []) do
    if Keyword.get(options, :score, false) do
      Connection.zrevrangebyscorewithscoreandlimit!(
        redis,
        failed_queue_key(namespace),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> decode_zset_withscores(options)
    else
      Connection.zrevrangebyscorewithlimit!(
        redis,
        failed_queue_key(namespace),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> maybe_decode(options)
    end
  end

  def retry_size(redis, namespace) do
    Connection.zcard!(redis, retry_queue_key(namespace))
  end

  def scheduled_size(redis, namespace) do
    Connection.zcard!(redis, scheduled_queue_key(namespace))
  end

  def failed_size(redis, namespace) do
    Connection.zcard!(redis, failed_queue_key(namespace))
  end

  def remove_enqueued_jobs(redis, namespace, queue, raw_jobs) do
    Connection.lrem!(redis, queue_key(namespace, queue), raw_jobs)
  end

  def remove_job(redis, namespace, queue, jid) do
    {:ok, job} = find_job(redis, namespace, jid, queue, false)
    Connection.lrem!(redis, queue_key(namespace, queue), job)
  end

  def remove_retry(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :retry, false)
    Connection.zrem!(redis, retry_queue_key(namespace), job)
  end

  def remove_retry_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, retry_queue_key(namespace), raw_jobs)
  end

  def dequeue_retry_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, retry_queue_key(namespace), raw_jobs)
  end

  def remove_scheduled(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :scheduled, false)
    Connection.zrem!(redis, scheduled_queue_key(namespace), job)
  end

  def remove_scheduled_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, scheduled_queue_key(namespace), raw_jobs)
  end

  def dequeue_scheduled_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, scheduled_queue_key(namespace), raw_jobs)
  end

  def remove_failed_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, failed_queue_key(namespace), raw_jobs)
  end

  def dequeue_failed_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, failed_queue_key(namespace), raw_jobs)
  end

  def list_queues(redis, namespace) do
    Connection.smembers!(redis, full_key(namespace, "queues"))
  end

  @doc """
  Find a current job by job id (but do not pop it)
  """
  def find_job(redis, namespace, jid, queue) do
    find_job(redis, namespace, jid, queue, true)
  end

  def find_job(redis, namespace, jid, :scheduled, convert) do
    redis
    |> Connection.zrangebyscore!(scheduled_queue_key(namespace))
    |> search_jobs(jid, convert)
  end

  def find_job(redis, namespace, jid, :retry, convert) do
    redis
    |> Connection.zrangebyscore!(retry_queue_key(namespace))
    |> search_jobs(jid, convert)
  end

  def find_job(redis, namespace, jid, queue, convert) do
    redis
    |> Connection.lrange!(queue_key(namespace, queue))
    |> search_jobs(jid, convert)
  end

  def search_jobs(jobs_serialized, jid) do
    search_jobs(jobs_serialized, jid, true)
  end

  def search_jobs(jobs_serialized, jid, true) do
    found_job =
      jobs_serialized
      |> Enum.map(&Job.decode/1)
      |> Enum.find(fn job -> job.jid == jid end)

    {:ok, found_job}
  end

  def search_jobs(jobs_serialized, jid, false) do
    found_job =
      jobs_serialized
      |> Enum.find(fn job_serialized ->
        job = Job.decode(job_serialized)
        job.jid == jid
      end)

    {:ok, found_job}
  end

  def to_job_serialized(queue, worker, args, options) do
    to_job_serialized(queue, worker, args, options, Time.unix_seconds())
  end

  def to_job_serialized(queue, worker, args, options, enqueued_at) when is_atom(worker) do
    to_job_serialized(queue, to_string(worker), args, options, enqueued_at)
  end

  def to_job_serialized(queue, "Elixir." <> worker, args, options, enqueued_at) do
    to_job_serialized(queue, worker, args, options, enqueued_at)
  end

  def to_job_serialized(queue, worker, args, options, enqueued_at) do
    jid = Keyword.get_lazy(options, :jid, fn -> UUID.uuid4() end)
    retry = Keyword.get_lazy(options, :max_retries, fn -> get_max_retries() end)

    job =
      %{
        queue: queue,
        retry: retry,
        class: worker,
        args: args,
        jid: jid,
        enqueued_at: enqueued_at
      }
      |> add_unique_attributes(options)

    {jid, job, Config.serializer().encode!(job)}
  end

  defp dequeue_scheduled_jobs(redis, namespace, queue_key, raw_jobs) do
    Script.eval!(redis, :scheduler_dequeue_jobs, [queue_key, full_key(namespace, "")], raw_jobs)
  end

  defp get_max_retries do
    :max_retries
    |> Config.get()
    |> Exq.Support.Coercion.to_integer()
  end

  defp add_failure_timestamp(job) do
    timestamp = Time.unix_seconds()

    job =
      if !job.failed_at do
        %{job | failed_at: timestamp}
      else
        job
      end

    %{job | retried_at: timestamp}
  end

  defp decode_zset_withscores(list, options) do
    raw? = Keyword.get(options, :raw, false)

    Enum.chunk_every(list, 2)
    |> Enum.map(fn [job, score] ->
      if raw? do
        {job, score}
      else
        {Job.decode(job), score}
      end
    end)
  end

  defp maybe_decode(list, options) do
    if Keyword.get(options, :raw, false) do
      list
    else
      Enum.map(list, &Job.decode/1)
    end
  end

  defp add_unique_attributes(job, options) do
    unique_for = Keyword.get(options, :unique_for, nil)

    if unique_for do
      unique_token =
        Keyword.get_lazy(options, :unique_token, fn ->
          string =
            Enum.join([job.queue, job.class] ++ Enum.map(job.args, &:erlang.phash2(&1)), ":")

          :crypto.hash(:sha256, string) |> Base.encode64()
        end)

      Map.put(job, :unique_for, unique_for)
      |> Map.put(:unique_until, to_string(Keyword.get(options, :unique_until, :success)))
      |> Map.put(:unique_token, unique_token)
      |> Map.put(:unlocks_at, job.enqueued_at + unique_for)
    else
      job
    end
  end

  defp unique_args(namespace, job, options) do
    if Keyword.get(options, :unique_check, false) do
      case job do
        %{unlocks_at: unlocks_at, unique_token: unique_token} ->
          unlocks_in = Enum.max([trunc((unlocks_at - Time.unix_seconds()) * 1000), 0])
          [unlocks_in, unique_key(namespace, unique_token)]

        _ ->
          [nil, nil]
      end
    else
      [nil, nil]
    end
  end

  # Returns
  # {
  #   [
  #     job_1_unique_key, job_1_queue_key,
  #     job_2_unique_key, job_2_queue_key,
  #     ...
  #   ],
  #   [
  #     job_1_jid, job_1_queue, job_1_score, job_1_job_serialized, job_1_unlocks_in,
  #     job_2_jid, job_2_queue, job_2_score, job_2_job_serialized, job_2_unlocks_in,
  #     ...
  #   ]
  # }
  defp extract_enqueue_all_keys_and_args(namespace, jobs) do
    {keys, job_attrs} =
      Enum.reduce(jobs, {[], []}, fn job, {keys_acc, job_attrs_acc} ->
        [queue, worker, args, options] = job

        {score, enqueued_at} =
          case options[:schedule] do
            {:at, at_time} ->
              {Time.time_to_score(at_time), Time.unix_seconds(at_time)}

            {:in, offset} ->
              at_time = Time.offset_from_now(offset)
              {Time.time_to_score(at_time), Time.unix_seconds(at_time)}

            _ ->
              {"0", Time.unix_seconds()}
          end

        {jid, job_data, job_serialized} =
          to_job_serialized(queue, worker, args, options, enqueued_at)

        [unlocks_in, unique_key] = unique_args(namespace, job_data, unique_check: true)

        # accumulating in reverse order for efficiency
        {
          [queue_key(namespace, queue), unique_key] ++ keys_acc,
          [unlocks_in, job_serialized, score, queue, jid] ++ job_attrs_acc
        }
      end)

    {Enum.reverse(keys), Enum.reverse(job_attrs)}
  end
end
