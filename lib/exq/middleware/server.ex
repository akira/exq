defmodule Exq.Middleware.Server do
  @moduledoc """
  Middleware Server is responsible for storing middleware chain that is evaluated
  when performing particular job. Middleware chain defaults to Stats, Job and Manager middlewares.

  To push new middleware you must create module with common interface. Interface is similar to `Plug`
  implementation. It has three functions, every function receives `Exq.Middlewares.Pipeline` structure
  and every function must return the same structure, modified or not.

  Basically, `before_work/1` function may update worker state, while `after_processed_work/1` and
  `after_failed_work/1` are for cleanup and notification stuff.

  For example, here is a valid middleware module:

  ```elixir
    defmodule MyMiddleware do
      @behaiour Exq.Middleware.Behaviour

      def before_work(pipeline) do
        # some functionality goes here...
        pipeline
      end

      def after_processed_work(pipeline) do
        # some functionality goes here...
        pipeline
      end

      def after_failed_work(pipeline) do
        # some functionality goes here...
        pipeline
      end
    end
  ```

  To add this module to middleware chain:

  ```elixir
    Exq.Middleware.Server.push(middleware_server_pid, MyMiddleware)
  ```
  """

  use GenServer

  @doc """
  Starts middleware server
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, default_middleware(opts), name: server_name(opts[:name]))
  end

  @doc """
  Adds specified `middleware` module into the end of middleware list. `middleware` should have
  `Exq.Middleware.Behaviour` behaviour
  """
  def push(pid, middleware) do
    GenServer.cast(pid, {:push, middleware})
  end

  @doc """
  Retrieves list of middleware modules
  """
  def all(pid) do
    GenServer.call(pid, :all)
  end

  @doc """
  Returns middleware server name
  """
  def server_name(name) do
    name = name || Exq.Support.Config.get(:name)
    "#{name}.Middleware.Server" |> String.to_atom()
  end

  @doc false
  def terminate(_reason, _state) do
    :ok
  end

  ## ===========================================================
  ## gen server callbacks
  ## ===========================================================

  def handle_cast({:push, middleware}, state) do
    {:noreply, List.insert_at(state, -1, middleware)}
  end

  def handle_call(:all, _from, state) do
    {:reply, state, state}
  end

  def init(args) do
    {:ok, args}
  end

  ## ===========================================================
  ## Internal Functions
  ## ===========================================================

  defp default_middleware([]), do: []
  defp default_middleware(opts), do: opts[:default_middleware]
end
