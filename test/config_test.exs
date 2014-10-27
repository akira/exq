Code.require_file "test_helper.exs", __DIR__
defmodule Exq.ConfigTest do
  use ExUnit.Case
  require Mix.Config

  test "Mix.Config should change the host." do
    assert Exq.Config.get(:host) == '127.0.0.1'
    Mix.Config.persist([exq: [host: '127.1.1.1']])
    assert Exq.Config.get(:host) == '127.1.1.1'
  end

end
