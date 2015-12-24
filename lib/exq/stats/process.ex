defmodule Exq.Stats.Process do
  @moduledoc """
  Struct for in progress worker
  """
  defstruct pid: nil, host: nil, job: nil, started_at: nil

  alias Exq.Support.Json

  @doc """
  Serialize process to JSON
  """
  def to_json(process) do
    formatted_pid = to_string(:io_lib.format("~p", [process.pid]))
    json = Enum.into([
      pid: formatted_pid,
      host: process.host,
      job: process.job,
      started_at: process.started_at], HashDict.new)

    Json.encode!(json)
  end
end
