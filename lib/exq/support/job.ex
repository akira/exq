defmodule Exq.Support.Job do
  @moduledoc """
  Serializeable Job format used by Exq
  """

  defstruct error_message: nil, error_class: nil, failed_at: nil, retry: false,
            retry_count: 0, processor: nil, queue: nil, class: nil, args: nil,
            jid: nil, finished_at: nil, enqueued_at: nil

  alias Exq.Support.Json

  def from_json(json_str) do
    json = Json.decode!(json_str)
    %Exq.Support.Job{
      args: Dict.get(json, "args"),
      class: Dict.get(json, "class"),
      enqueued_at: Dict.get(json, "enqueued_at"),
      error_message: Dict.get(json, "error_message"),
      error_class: Dict.get(json, "error_class"),
      failed_at: Dict.get(json, "failed_at"),
      finished_at: Dict.get(json, "finished_at"),
      jid: Dict.get(json, "jid"),
      processor: Dict.get(json, "processor"),
      queue: Dict.get(json, "queue"),
      retry: Dict.get(json, "retry"),
      retry_count: Dict.get(json, "retry_count")}
  end

  def to_json(job) do
    json = Enum.into([
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
      retry_count: job.retry_count], HashDict.new)
    Json.encode!(json)
  end
end
