defmodule Exq.Serializers.JsonSerializer do
  @behaviour Exq.Serializers.Behaviour
  alias Exq.Support.Config

  defp json_library do
    Config.get(:json_library)
  end

  def decode(json) do
    json_library().decode(json)
  end

  def encode(e) do
    json_library().encode(e)
  end

  def decode!(json) do
    json_library().decode!(json)
  end

  def encode!(e) do
    json_library().encode!(e)
  end

  def decode_job(serialized) do
    deserialized = decode!(serialized)

    queuing_timeout = Map.get(deserialized, "queuing_timeout")

    queuing_timeout =
      if is_integer(queuing_timeout) do
        queuing_timeout
      else
        :infinity
      end

    execution_timeout = Map.get(deserialized, "execution_timeout")

    execution_timeout =
      if is_integer(execution_timeout) do
        execution_timeout
      else
        :infinity
      end

    %Exq.Support.Job{
      args: Map.get(deserialized, "args"),
      class: Map.get(deserialized, "class"),
      enqueued_at: Map.get(deserialized, "enqueued_at"),
      error_message: Map.get(deserialized, "error_message"),
      error_class: Map.get(deserialized, "error_class"),
      failed_at: Map.get(deserialized, "failed_at"),
      retried_at: Map.get(deserialized, "retried_at"),
      finished_at: Map.get(deserialized, "finished_at"),
      jid: Map.get(deserialized, "jid"),
      processor: Map.get(deserialized, "processor"),
      queue: Map.get(deserialized, "queue"),
      retry: Map.get(deserialized, "retry"),
      retry_count: Map.get(deserialized, "retry_count"),
      queuing_timeout: queuing_timeout,
      execution_timeout: execution_timeout
    }
  end

  def encode_job(job) do
    deserialized = %{
      args: job.args,
      class: job.class,
      enqueued_at: job.enqueued_at,
      error_message: job.error_message,
      error_class: job.error_class,
      failed_at: job.failed_at,
      retried_at: job.retried_at,
      finished_at: job.finished_at,
      jid: job.jid,
      processor: job.processor,
      queue: job.queue,
      retry: job.retry,
      retry_count: job.retry_count,
      queuing_timeout: job.queuing_timeout,
      execution_timeout: job.execution_timeout
    }

    encode!(deserialized)
  end

  def decode_process(serialized) do
    deserialized = decode!(serialized)

    %Exq.Support.Process{
      pid: Map.get(deserialized, "pid"),
      host: Map.get(deserialized, "host"),
      job: Map.get(deserialized, "job"),
      started_at: Map.get(deserialized, "started_at")
    }
  end

  def encode_process(process) do
    formatted_pid = to_string(:io_lib.format("~p", [process.pid]))

    deserialized =
      Enum.into(
        [
          pid: formatted_pid,
          host: process.host,
          job: process.job,
          started_at: process.started_at
        ],
        Map.new()
      )

    encode!(deserialized)
  end
end
