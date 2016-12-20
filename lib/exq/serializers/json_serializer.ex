defmodule Exq.Serializers.JsonSerializer do
  @behaviour Exq.Serializers.Behaviour

  def decode(json) do
    Poison.decode(json)
  end

  def encode(e) do
    Poison.encode(e)
  end

  def decode!(json) do
    Poison.decode!(json)
  end

  def encode!(e) do
    Poison.encode!(e)
  end

  def decode_job(serialized) do
    deserialized = decode!(serialized)
    %Exq.Support.Job{
      args: Dict.get(deserialized, "args"),
      class: Dict.get(deserialized, "class"),
      enqueued_at: Dict.get(deserialized, "enqueued_at"),
      error_message: Dict.get(deserialized, "error_message"),
      error_class: Dict.get(deserialized, "error_class"),
      failed_at: Dict.get(deserialized, "failed_at"),
      finished_at: Dict.get(deserialized, "finished_at"),
      jid: Dict.get(deserialized, "jid"),
      processor: Dict.get(deserialized, "processor"),
      queue: Dict.get(deserialized, "queue"),
      retry: Dict.get(deserialized, "retry"),
      retry_count: Dict.get(deserialized, "retry_count")}
  end

  def encode_job(job) do
    deserialized = %{
      args: job.args,
      class: job.class,
      enqueued_at: job.enqueued_at,
      error_message: job.error_message,
      error_class: job.error_class,
      failed_at: job.failed_at,
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
      pid: Dict.get(deserialized, "pid"),
      host: Dict.get(deserialized, "host"),
      job: Dict.get(deserialized, "job"),
      started_at: Dict.get(deserialized, "started_at")
    }
  end

  def encode_process(process) do
    formatted_pid = to_string(:io_lib.format("~p", [process.pid]))
    deserialized = Enum.into([
      pid: formatted_pid,
      host: process.host,
      job: process.job,
      started_at: process.started_at], HashDict.new)

    encode!(deserialized)
  end
end
