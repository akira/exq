defmodule Exq.Backoff.Behaviour do
  use Behaviour

  @callback offset(job :: %Exq.Support.Job{}) :: number
end
