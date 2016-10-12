defmodule Exq.Support.Job do
  @moduledoc """
  Serializable Job format used by Exq
  """

  defstruct error_message: nil, error_class: nil, failed_at: nil, retry: false,
            retry_count: 0, processor: nil, queue: nil, class: nil, args: nil,
            jid: nil, finished_at: nil, enqueued_at: nil

  alias Exq.Support.Config

  def decode(serialized) do
    Config.serializer.decode_job(serialized)
  end

  def encode(job) do
    Config.serializer.encode_job(job)
  end
end
