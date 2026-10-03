defmodule MetadataTest do
  use ExUnit.Case
  alias Exq.Worker.Metadata

  @job %{args: [1, 2, 3]}

  setup do
    {:ok, _} = Metadata.start_link(%{})
    {:ok, metadata: Metadata.server_name(nil)}
  end

  test "associate job to worker pid", %{metadata: metadata} do
    pid =
      spawn_link(fn ->
        receive do
          :fetch_and_quit ->
            assert Exq.worker_job() == @job
            :ok
        end
      end)

    assert Metadata.associate(metadata, pid, @job) == :ok
    assert Metadata.lookup(metadata, pid) == @job
    assert Exq.worker_job(Exq, pid) == @job
    send(pid, :fetch_and_quit)
    Process.sleep(50)

    assert Metadata.lookup(metadata, pid) == nil
  end

  test "re-associating a worker updates the job without replacing its monitor", %{
    metadata: metadata
  } do
    pid = spawn_link(fn -> receive do: (:finish -> :ok) end)
    assert :ok = Metadata.associate(metadata, pid, @job)
    [{^pid, ref, @job}] = :ets.lookup(metadata, pid)

    updated = %{args: [4, 5, 6]}
    assert :ok = Metadata.associate(metadata, pid, updated)
    assert [{pid, ref, updated}] == :ets.lookup(metadata, pid)
    send(pid, :finish)
  end

  test "custom name" do
    {:ok, _} = Metadata.start_link(%{name: ExqTest})

    pid =
      spawn_link(fn ->
        receive do
          :fetch_and_quit ->
            assert Exq.worker_job(ExqTest) == @job
            :ok
        end
      end)

    assert Metadata.associate(Metadata.server_name(ExqTest), pid, @job) == :ok
    assert Exq.worker_job(ExqTest, pid) == @job
    send(pid, :fetch_and_quit)
    Process.sleep(50)
  end
end
