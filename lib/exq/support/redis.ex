defmodule Exq.Support.Redis do
  require Logger

  @doc """
  Rescue GenServer timeout.
  """
  def rescue_timeout(f, options \\ []) do
    try do
      f.()
    catch
      :exit, {:timeout, info} ->
        Logger.info("Manager timeout occurred #{inspect(info)}")
        Keyword.get(options, :timeout_return_value, nil)
    end
  end

  def with_retry_on_connection_error(f, times) when times <= 0 do
    f.()
  end

  def with_retry_on_connection_error(f, times) when times > 0 do
    try do
      case f.() do
        {:error, %Redix.ConnectionError{} = exception} ->
          Logger.error("Retrying redis connection error: #{inspect(exception)}")
          with_retry_on_connection_error(f, times - 1)

        result ->
          result
      end
    rescue
      exception in [Redix.ConnectionError] ->
        Logger.error("Retrying redis connection error: #{inspect(exception)}")
        with_retry_on_connection_error(f, times - 1)
    end
  end
end
