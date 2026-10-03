defmodule Exq.Support.Job do
  @moduledoc """
  Serializable Job format used by Exq.

  `meta` contains additional string-keyed fields supplied with
  the `meta:` enqueue option or decoded from unknown payload fields. The JSON
  serializer stores them at the top level, not inside a metadata object.
  Built-in job fields cannot be overridden. Access metadata through `Exq.worker_job().meta`.
  """

  defstruct error_message: nil,
            error_class: nil,
            retried_at: nil,
            failed_at: nil,
            retry: false,
            retry_count: 0,
            processor: nil,
            queue: nil,
            class: nil,
            args: nil,
            jid: nil,
            finished_at: nil,
            enqueued_at: nil,
            unique_for: nil,
            unique_until: nil,
            unique_token: nil,
            unlocks_at: nil,
            meta: %{}

  @type t :: %__MODULE__{}

  alias Exq.Support.Config

  @doc false
  def payload_fields do
    %__MODULE__{}
    |> Map.from_struct()
    |> Map.delete(:meta)
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
  end

  @doc false
  def to_payload(%__MODULE__{} = job), do: to_payload(Map.from_struct(job))

  def to_payload(job) do
    {meta, payload} = Map.pop(job, :meta, %{})
    Map.merge(payload, validate_meta!(meta))
  end

  @doc """
  Returns valid job metadata or raises `ArgumentError`.

  Requires a map with string keys. Built-in job fields cannot be overridden.
  """
  def validate_meta!(meta) when is_map(meta) and map_size(meta) == 0, do: meta

  def validate_meta!(meta) when is_map(meta) do
    fields = payload_fields()

    Enum.each(Map.keys(meta), fn key ->
      unless is_binary(key) do
        raise ArgumentError, "meta must be a map with string keys"
      end

      if key in fields do
        raise ArgumentError, "meta cannot override job field #{inspect(key)}"
      end
    end)

    meta
  end

  def validate_meta!(_meta) do
    raise ArgumentError, "meta must be a map with string keys"
  end

  def decode(serialized) do
    Config.serializer().decode_job(serialized)
  end

  def encode(nil), do: nil

  def encode(%__MODULE__{} = job) do
    encode(%{
      error_message: encode(job.error_message),
      error_class: job.error_class,
      failed_at: job.failed_at,
      retried_at: job.retried_at,
      retry: job.retry,
      retry_count: job.retry_count,
      processor: job.processor,
      queue: job.queue,
      class: job.class,
      args: job.args,
      jid: job.jid,
      finished_at: job.finished_at,
      enqueued_at: job.enqueued_at,
      unique_for: job.unique_for,
      unique_until: job.unique_until,
      unique_token: job.unique_token,
      unlocks_at: job.unlocks_at,
      meta: job.meta
    })
  end

  def encode(%RuntimeError{message: message}), do: %{message: message}

  def encode(%{} = job_map) do
    job_map =
      case Map.fetch(job_map, :error_message) do
        {:ok, val} ->
          Map.put(job_map, :error_message, encode(val))

        :error ->
          job_map
      end

    Config.serializer().encode_job(job_map)
  end

  def encode(val), do: val
end
