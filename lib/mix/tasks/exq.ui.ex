defmodule Mix.Tasks.Exq.Ui do
  use Mix.Task

  @shortdoc "Starts the Exq UI Server"

  def run(args) do
    IO.puts "Started ExqUI"
    #Exq.start([host: '', port: port, namespace: namespace, queues: queues]) 
    Plug.Adapters.Cowboy.http Exq.RouterPlug, [namespace: ""]
    
    :timer.sleep(:infinity)
  end

end