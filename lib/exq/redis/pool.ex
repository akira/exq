defmodule Exq.Redis.Pool do
  @pool_size Application.get_env(:exq, "pool_size", 1)

  def child_spec(redix_opts) do
    # Specs for the Redix connections.

    children =
      for i <- 0..(@pool_size - 1) do
        name = Keyword.get(redix_opts, :name, :redix)
        opts = Keyword.merge(redix_opts, [name: :"#{name}_#{i}"])

        Supervisor.child_spec({Redix, opts}, id: {Redix, i})
      end

    # Spec for the supervisor that will supervise the Redix connections.
    %{
      id: RedixSupervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  def command(conn, command, opts \\ []) do
    Redix.command(:"#{conn}_#{random_index()}", command, opts)
  end

  def pipeline(conn, commands, opts \\ []) do
    Redix.pipeline(:"#{conn}_#{random_index()}", commands, opts)
  end

  def pipeline!(conn, commands, opts \\ []) do
    Redix.pipeline!(:"#{conn}_#{random_index()}", commands, opts)
  end

  defp random_index() do
    rem(System.unique_integer([:positive]), @pool_size)
  end
end