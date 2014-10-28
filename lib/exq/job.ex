defmodule Exq.Job do
  defstruct error_message: nil, error_class: nil, failed_at: nil, retry: false, retry_count: 0, processor: nil, queue: nil, class: nil, args: nil, jid: nil, finished_at: nil, enqueued_at: nil
end
