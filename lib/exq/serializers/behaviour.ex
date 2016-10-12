defmodule Exq.Serializers.Behaviour do
  use Behaviour

  @callback decode(any) :: any
  @callback decode!(any) :: any
  @callback encode(any) :: any
  @callback encode!(any) :: any

  @callback encode_job(any) :: any
  @callback decode_job(any) :: any
  @callback encode_process(any) :: any
  @callback decode_process(any) :: any
end
