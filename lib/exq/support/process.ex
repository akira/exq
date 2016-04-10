defmodule Exq.Support.Process do
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

  @doc """
  Decode JSON into process
  """
  def from_json(json_str) do
    json = Json.decode!(json_str)
    %Exq.Support.Process{
      pid: Dict.get(json, "pid"),
      host: Dict.get(json, "host"),
      job: Dict.get(json, "job"),
      started_at: Dict.get(json, "started_at")
    }
  end
end
