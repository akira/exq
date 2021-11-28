defmodule Exq.Support.Process do
  @moduledoc """
  Struct for in progress worker.
  """
  defstruct pid: nil, host: nil, payload: nil, run_at: nil, queue: nil

  alias Exq.Support.Config

  @doc """
  Serialize process to JSON.
  """
  def encode(%__MODULE__{} = process) do
    Config.serializer().encode_process(%{
      pid: process.pid,
      host: process.host,
      payload: Exq.Support.Job.encode(process.payload),
      run_at: process.run_at,
      queue: process.queue
    })
  end

  @doc """
  Decode JSON into process.
  """
  def decode(serialized) do
    Config.serializer().decode_process(serialized)
  end
end
