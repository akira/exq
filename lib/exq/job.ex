defmodule Exq.Job do
  defstruct queue: nil, class: nil, args: nil, jid: nil, finished_at: nil, enqueued_at: nil
end
