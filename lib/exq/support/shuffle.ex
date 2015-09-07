#http://en.literateprograms.org/index.php?title=Special:DownloadCode/Fisher-Yates_shuffle_(Erlang)
defmodule Exq.Support.Shuffle do
  def shuffle(list)  do
    shuffle(list, [])
  end
  def shuffle([], acc) do
    acc
  end
  def shuffle(list, acc) do
    {leading, [h | t]} = :lists.split(:random.uniform(length(list)) - 1, list)
    shuffle(leading ++ t, [h | acc])
  end
end
