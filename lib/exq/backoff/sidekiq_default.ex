defmodule Exq.Backoff.SidekiqDefault do
  @behaviour Exq.Backoff.Behaviour
  alias Exq.Support.Randomize

  def offset(job) do
    :math.pow(job.retry_count, 4) + 15 + (Randomize.random(30) * (job.retry_count + 1))
  end
end
