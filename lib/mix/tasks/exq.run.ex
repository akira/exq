defmodule Mix.Tasks.Exq.Run do
  use Mix.Task

  @shortdoc "Starts the Exq worker"

  def run(args) do
    {opts, args, _} = OptionParser.parse args,
      switches: [host: :string, port: :integer, namespace: :string, queues: :string, webport: :integer]
    app = parse_app(args)
    if app do
      app.start(nil)
    end
    opts = Keyword.put(opts, :host, to_char_list(Keyword.get(opts, :host, "127.0.0.1")))

    {:ok, _pid} = Exq.start(opts)
    IO.puts "Started Exq with redis options: Host: #{opts[:host]}, Port: #{opts[:port]}, Namespace: #{opts[:namespace]}"
    :timer.sleep(:infinity)
  end

  def parse_app([h|t]) when is_binary(h) and h != "" do
    {Module.concat([h]), t}
  end

  def parse_app([h|t]) when is_atom(h) and h != :"" do
    {h, t}
  end

  def parse_app(_) do
    nil
    #raise Mix.Error, message: "invalid arguments, expected an applicaiton as first argument"
  end

end
