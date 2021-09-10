defmodule Exq.Support.Job do
  @moduledoc """
  Serializable Job format used by Exq.
  """

  defstruct error_message: nil,
            error_class: nil,
            retried_at: nil,
            failed_at: nil,
            retry: false,
            retry_count: 0,
            processor: nil,
            queue: nil,
            class: nil,
            args: nil,
            jid: nil,
            finished_at: nil,
            enqueued_at: nil

  alias Exq.Support.Config

  def decode(serialized) do
    Config.serializer().decode_job(serialized)
  end

  def encode(nil), do: nil

  def encode(%__MODULE__{} = job) do
    encode(%{
      error_message: encode(job.error_message),
      error_class: job.error_class,
      failed_at: job.failed_at,
      retried_at: job.retried_at,
      retry: job.retry,
      retry_count: job.retry_count,
      processor: job.processor,
      queue: job.queue,
      class: job.class,
      args: job.args,
      jid: job.jid,
      finished_at: job.finished_at,
      enqueued_at: job.enqueued_at
    })
  end

  def encode(%RuntimeError{message: message}), do: %{message: message}

  def encode(%{} = job_map) do
    job_map =
      case Map.fetch(job_map, :error_message) do
        {:ok, val} ->
          Map.put(job_map, :error_message, encode(val))

        :error ->
          job_map
      end

    Config.serializer().encode_job(job_map)
  end

  def encode(val), do: val
end
