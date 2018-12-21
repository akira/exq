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

    assert_raise ArgumentError, fn ->
      Metadata.lookup(metadata, pid)
    end
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
