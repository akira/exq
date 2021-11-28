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
      retry_count: Map.get(deserialized, "retry_count")
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
      retry_count: job.retry_count
    }

    encode!(deserialized)
  end

  def decode_process(serialized) do
    deserialized = decode!(serialized)

    %Exq.Support.Process{
      pid: Map.get(deserialized, "pid"),
      host: Map.get(deserialized, "host"),
      payload:
        Map.get(deserialized, "payload")
        |> Exq.Support.Job.decode(),
      run_at: Map.get(deserialized, "run_at"),
      queue: Map.get(deserialized, "queue")
    }
  end

  def encode_process(process) do
    deserialized =
      Enum.into(
        [
          pid: process.pid,
          host: process.host,
          payload: process.payload,
          run_at: process.run_at,
          queue: process.queue
        ],
        Map.new()
      )

    encode!(deserialized)
  end

  def encode_node(node) do
    encode!(Map.from_struct(node))
  end

  def decode_node(serialized) do
    deserialized = decode!(serialized)

    %Exq.Support.Node{
      hostname: Map.get(deserialized, "hostname"),
      identity: Map.get(deserialized, "identity"),
      started_at: Map.get(deserialized, "started_at"),
      pid: Map.get(deserialized, "pid"),
      queues: Map.get(deserialized, "queues"),
      labels: Map.get(deserialized, "labels"),
      tag: Map.get(deserialized, "tag"),
      busy: Map.get(deserialized, "busy"),
      quiet: Map.get(deserialized, "quiet"),
      concurrency: Map.get(deserialized, "concurrency")
    }
  end
end
