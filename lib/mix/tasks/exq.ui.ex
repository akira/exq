defmodule Mix.Tasks.Exq.Ui do
  use Mix.Task

  @shortdoc "Starts the Exq UI Server"

  def run(args) do
    
    
    {opts, args, _} = OptionParser.parse args,
      switches: [host: :string, port: :integer, namespace: :string, queues: :string, webport: :integer]

    webport = Keyword.get(opts, :webport, 4040)
    opts = Keyword.put(opts, :host, to_char_list(Keyword.get(opts, :host, "127.0.0.1")))
    Exq.start(opts) 
    IO.puts "Started ExqUI on Port #{webport}"
    Plug.Adapters.Cowboy.http Exq.RouterPlug, [namespace: ""], port: webport
    
    :timer.sleep(:infinity)
  end

end