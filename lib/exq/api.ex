defmodule Exq.Api do
  @moduledoc """
  Interface for retrieving Exq stats.

  Pid is currently Exq.Api process.
  """

  def start_link(opts \\ []) do
    Exq.start_link(Keyword.put(opts, :mode, :api))
  end

  @doc """
  List of queues with jobs (empty queues are deleted).

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, queues}` - list of queue

  """
  def queues(pid) do
    GenServer.call(pid, :queues)
  end

  @doc """
  Clear / Remove queue

  Expected args:
    * `pid` - Exq.Api process
    * `queue` - Queue name

  Returns:
    * `{:ok, queues}` - list of queue

  """
  def remove_queue(pid, queue) do
    GenServer.call(pid, {:remove_queue, queue})
  end

  @doc """
  Number of busy workers

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, num_busy}` - number of busy workers

  """
  def busy(pid) do
    GenServer.call(pid, :busy)
  end

  @doc """
  List of worker nodes currently running
  """

  def nodes(pid) do
    GenServer.call(pid, :nodes)
  end

  @doc """
  List of processes currently running

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, [processes]}`

  """
  def processes(pid) do
    GenServer.call(pid, :processes)
  end

  def clear_processes(pid) do
    GenServer.call(pid, :clear_processes)
  end

  @doc """
  List jobs enqueued

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, [{queue, [jobs]}, {queue, [jobs]}]}`

  """
  def jobs(pid) do
    GenServer.call(pid, :jobs)
  end

  @doc """
  List jobs enqueued

  Expected args:
    * `pid` - Exq.Api process
    * `queue` - Queue name
    * `options`
      - size: (integer) size of list
      - offset: (integer) start offset of the list
      - raw: (boolean) whether to deserialize the job

  Returns:
    * `{:ok, [jobs]}`

  """
  def jobs(pid, queue, options \\ []) do
    GenServer.call(pid, {:jobs, queue, options})
  end

  @doc """
  List jobs that will be retried because they previously failed and have not exceeded their retry_count.

  Expected args:
    * `pid` - Exq.Api process
    * `options`
      - score: (boolean) whether to include job score
      - size: (integer) size of list
      - offset: (integer) start offset of the list

  Returns:
    * `{:ok, [jobs]}`

  """
  def retries(pid, options \\ []) do
    GenServer.call(pid, {:retries, options})
  end

  @doc """
  List jobs that are enqueued and scheduled to be run at a future time.

  Expected args:
    * `pid` - Exq.Api process
    * `options`
      - score: (boolean) whether to include job score
      - size: (integer) size of list
      - offset: (integer) start offset of the list

  Returns:
    * `{:ok, [jobs]}`

  """
  def scheduled(pid, options \\ []) do
    GenServer.call(pid, {:jobs, :scheduled, options})
  end

  @doc """
  List jobs that are enqueued and scheduled to be run at a future time, along with when they are scheduled to run.

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, [{job, scheduled_at}]}`

  """
  def scheduled_with_scores(pid) do
    GenServer.call(pid, {:jobs, :scheduled_with_scores})
  end

  def find_job(pid, queue, jid) do
    GenServer.call(pid, {:find_job, queue, jid})
  end

  @doc """
  Removes a job from the queue specified.

  Expected args:
    * `pid` - Exq.Api process
    * `queue` - The name of the queue to remove the job from
    * `jid` - Unique identifier for the job

  Returns:
    * `:ok`

  """
  @deprecated "use remove_enqueued_jobs/3"
  def remove_job(pid, queue, jid) do
    GenServer.call(pid, {:remove_job, queue, jid})
  end

  @doc """
  Removes a job from the queue specified.

  Expected args:
    * `pid` - Exq.Api process
    * `queue` - The name of the queue to remove the job from
    * `raw_job` - raw json encoded job value

  Returns:
    * `:ok`

  """
  def remove_enqueued_jobs(pid, queue, raw_jobs) do
    GenServer.call(pid, {:remove_enqueued_jobs, queue, raw_jobs})
  end

  @doc """
  A count of the number of jobs in the queue, for each queue.

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, [{queue, num_jobs}, {queue, num_jobs}]}`

  """
  def queue_size(pid) do
    GenServer.call(pid, :queue_size)
  end

  @doc """
  A count of the number of jobs in the queue, for a provided queue.

  Expected args:
    * `pid` - Exq.Api process
    * `queue` - The name of the queue to find the number of jobs for

  Returns:
    * `{:ok, num_jobs}`

  """
  def queue_size(pid, queue) do
    GenServer.call(pid, {:queue_size, queue})
  end

  @doc """
  List jobs that have failed and will not retry, as they've exceeded their retry count.

  Expected args:
    * `pid` - Exq.Api process
    * `options`
      - score: (boolean) whether to include job score
      - size: (integer) size of list
      - offset: (integer) start offset of the list

  Returns:
    * `{:ok, [jobs]}`

  """
  def failed(pid, options \\ []) do
    GenServer.call(pid, {:failed, options})
  end

  @deprecated "use find_failed/4"
  def find_failed(pid, jid) do
    GenServer.call(pid, {:find_failed, jid})
  end

  @doc """
  Find failed job

  Expected args:
    * `pid` - Exq.Api process
    * `score` - Job score
    * `jid` - Job jid
    * `options`
      - raw: (boolean) whether to deserialize the job

  Returns:
    * `{:ok, job}`

  """
  def find_failed(pid, score, jid, options \\ []) do
    GenServer.call(pid, {:find_failed, score, jid, options})
  end

  @doc """
  Removes a job in the queue of jobs that have failed and exceeded their retry count.

  Expected args:
    * `pid` - Exq.Api process
    * `jid` - Unique identifier for the job

  Returns:
    * `:ok`

  """
  @deprecated "use remove_failed_jobs/2"
  def remove_failed(pid, jid) do
    GenServer.call(pid, {:remove_failed, jid})
  end

  @doc """
  Removes jobs from dead queue.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `:ok`

  """
  def remove_failed_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:remove_failed_jobs, raw_jobs})
  end

  def clear_failed(pid) do
    GenServer.call(pid, :clear_failed)
  end

  @doc """
  Re Enqueue jobs from dead queue.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `{:ok, num_enqueued}`

  """
  def dequeue_failed_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:dequeue_failed_jobs, raw_jobs})
  end

  @doc """
  Number of jobs that have failed and exceeded their retry count.

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, num_failed}` - number of failed jobs

  """
  def failed_size(pid) do
    GenServer.call(pid, :failed_size)
  end

  @deprecated "use find_retry/4"
  def find_retry(pid, jid) do
    GenServer.call(pid, {:find_retry, jid})
  end

  @doc """
  Find job in retry queue

  Expected args:
    * `pid` - Exq.Api process
    * `score` - Job score
    * `jid` - Job jid
    * `options`
      - raw: (boolean) whether to deserialize the job

  Returns:
    * `{:ok, job}`

  """
  def find_retry(pid, score, jid, options \\ []) do
    GenServer.call(pid, {:find_retry, score, jid, options})
  end

  @doc """
  Removes a job in the retry queue from being enqueued again.

  Expected args:
    * `pid` - Exq.Api process
    * `jid` - Unique identifier for the job

  Returns:
    * `:ok`

  """
  @deprecated "use remove_retry_jobs/2"
  def remove_retry(pid, jid) do
    GenServer.call(pid, {:remove_retry, jid})
  end

  @doc """
  Removes jobs from retry queue.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `:ok`

  """
  def remove_retry_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:remove_retry_jobs, raw_jobs})
  end

  def clear_retries(pid) do
    GenServer.call(pid, :clear_retries)
  end

  @doc """
  Re enqueue jobs from retry queue immediately.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `{:ok, num_enqueued}`

  """
  def dequeue_retry_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:dequeue_retry_jobs, raw_jobs})
  end

  @doc """
  Number of jobs in the retry queue.

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, num_retry}` - number of jobs to be retried

  """
  def retry_size(pid) do
    GenServer.call(pid, :retry_size)
  end

  @deprecated "use find_scheduled/4"
  def find_scheduled(pid, jid) do
    GenServer.call(pid, {:find_scheduled, jid})
  end

  @doc """
  Find job in scheduled queue

  Expected args:
    * `pid` - Exq.Api process
    * `score` - Job score
    * `jid` - Job jid
    * `options`
      - raw: (boolean) whether to deserialize the job

  Returns:
    * `{:ok, job}`

  """
  def find_scheduled(pid, score, jid, options \\ []) do
    GenServer.call(pid, {:find_scheduled, score, jid, options})
  end

  @doc """
  Removes a job scheduled to run in the future from being enqueued.

  Expected args:
    * `pid` - Exq.Api process
    * `jid` - Unique identifier for the job

  Returns:
    * `:ok`

  """
  @deprecated "use remove_scheduled_jobs/2"
  def remove_scheduled(pid, jid) do
    GenServer.call(pid, {:remove_scheduled, jid})
  end

  @doc """
  Removes jobs from scheduled queue.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `:ok`

  """
  def remove_scheduled_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:remove_scheduled_jobs, raw_jobs})
  end

  def clear_scheduled(pid) do
    GenServer.call(pid, :clear_scheduled)
  end

  @doc """
  Enqueue jobs from scheduled queue immediately.

  Expected args:
    * `pid` - Exq.Api process
    * `raw_job` - raw json encoded job value

  Returns:
    * `{:ok, num_enqueued}`

  """
  def dequeue_scheduled_jobs(pid, raw_jobs) do
    GenServer.call(pid, {:dequeue_scheduled_jobs, raw_jobs})
  end

  @doc """
  Number of scheduled jobs enqueued.

  Expected args:
    * `pid` - Exq.Api process

  Returns:
    * `{:ok, num_scheduled}` - number of scheduled jobs enqueued

  """
  def scheduled_size(pid) do
    GenServer.call(pid, :scheduled_size)
  end

  @doc """
  Return stat for given key.

  Examples of keys are `processed` and `failed`.

  Expected args:
    * `pid` - Exq.Api process
    * `key` - Key for stat
    * `queue` - Queue name

  Returns:
    * `{:ok, stat}` stat for key

  """
  def stats(pid, key) do
    GenServer.call(pid, {:stats, key})
  end

  def stats(pid, key, dates) when is_list(dates) do
    GenServer.call(pid, {:stats, key, dates})
  end

  def stats(pid, key, date) do
    with {:ok, [count]} <- GenServer.call(pid, {:stats, key, [date]}) do
      {:ok, count}
    end
  end

  def realtime_stats(pid) do
    GenServer.call(pid, :realtime_stats)
  end

  def retry_job(pid, jid) do
    GenServer.call(pid, {:retry_job, jid})
  end
end
