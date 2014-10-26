defmodule Exq.FailedJob do
  defstruct args: nil, class: "ExqGenericError", error_message: nil, error_class: nil, failed_at: nil, queue: nil, retry: false, retried_at: nil, retry_count: nil, jid: nil, fid: nil
end
