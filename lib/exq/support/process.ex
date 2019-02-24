defmodule Exq.Support.Process do
  @moduledoc """
  Struct for in progress worker
  """
  defstruct pid: nil, host: nil, job: nil, started_at: nil

  alias Exq.Support.Config

  @doc """
  Serialize process to JSON
  """
  def encode(%__MODULE__{} = process) do
    Config.serializer().encode_process(%{
      pid: process.pid,
      host: process.host,
      job: Exq.Support.Job.encode(process.job),
      started_at: process.started_at
    })
  end

  @doc """
  Decode JSON into process
  """
  def decode(serialized) do
    Config.serializer().decode_process(serialized)
  end
end
