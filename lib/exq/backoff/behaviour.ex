defmodule Exq.Backoff.Behaviour do
  @callback offset(job :: %Exq.Support.Job{}) :: number
end
