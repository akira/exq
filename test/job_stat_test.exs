Code.require_file "test_helper.exs", __DIR__

defmodule JobStatTest do
  use ExUnit.Case
  import ExqTestUtil
  use Timex

  alias Exq.Redis.JobStat

  setup do
    TestRedis.setup
    on_exit(fn -> TestRedis.teardown end)
    Tzdata.EtsHolder.start_link

    :ok
  end

  test "show realtime statistics" do
    Exq.start_link
    state = :sys.get_state(Exq)

    {:ok, time1} = DateFormat.parse("2016-01-07T13:30:00+00", "{ISO}")
    {:ok, time2} = DateFormat.parse("2016-01-07T14:05:15+00", "{ISO}")

    JobStat.record_processed(state.redis, "test", nil, time1)
    JobStat.record_processed(state.redis, "test", nil, time2)
    JobStat.record_processed(state.redis, "test", nil, time1)
    JobStat.record_failure(state.redis, "test", nil, nil, time1)
    JobStat.record_failure(state.redis, "test", nil, nil, time2)

    Exq.Enqueuer.Server.start_link(name: ExqE)
    {:ok, failures, successes} = Exq.Api.realtime_stats(ExqE)

    assert  List.keysort(failures, 0) == [{"2016-01-07 13:30:00 +0000", "1"}, {"2016-01-07 14:05:15 +0000", "1"}]
    assert List.keysort(successes, 0) == [{"2016-01-07 13:30:00 +0000", "2"}, {"2016-01-07 14:05:15 +0000", "1"}]
  end
end
