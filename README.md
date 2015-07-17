# Exq

[![Build Status](https://travis-ci.org/akira/exq.png?branch=master)](https://travis-ci.org/akira/exq?branch=master)

Exq is a job processing library compatible with Resque / Sidekiq for the [Elixir](http://elixir-lang.org) language.

Exq uses Redis as a store for background processing jobs.  It is especially useful for integrating
with Ruby / Rails projects that already use Resque / Sidekiq for background jobs.

## Getting Started:

This assumes you have an instance of [Redis](http://redis.io/) to use.

### Installation:
Add exq to your mix.exs deps (replace version with the latest hex.pm package version):

```elixir
  defp deps do
    [
      # ... other deps
      {:exq, "~> 0.1.3"}
    ]
  end
```

Then run ```mix deps.get```.

### Configuration:

By default, Exq will use configuration from your config.exs file.  You can use this
to configure your Redis host, port, as well as namespace (which helps isolate the data in Redis).
The "concurrency" setting will let you configure the amount of concurrent workers that will be allowed, or :infinite to disable any throttling.

```elixir
config :exq,
  host: '127.0.0.1',
  port: 6379,
  password: "optional_redis_auth",
  namespace: "exq",
  concurrency: :infinite,
  queues: ["default"]
```

### Concurrency:

Exq supports concurrency setting per queue.  You can specify the same ```concurrency``` option to apply to each queue or specify it based on a per queue basis.

Concurrency for each queue will be set at ```1000```:

```elixir
config :exq,
  host: '127.0.0.1',
  port: 6379,
  namespace: "exq",
  concurrency: 1000,
  queues: ["default"]
```

Concurrency for ```q1``` is set at ```10_000``` while ```q2``` is set at ```10```:

```elixir
config :exq,
  host: '127.0.0.1',
  port: 6379,
  namespace: "exq",
  queues: [{"q1", 10_000}, {"q2", 10}]
```

### OTP Application:

You can add Exq into your OTP application list, and it will start an instance of Exq along with your application startup.  It will use the configuration from your ```config.exs``` file.

```elixir
  def application do
    [
      applications: [:logger, :exq],
      #other stuff...
    ]
  end
```

When using Exq through OTP, it will register a process under the name ```:exq``` - you can use this atom where expecting a process name in the Exq module.

## Starting Exq manually:

You can also start Exq manually and set configuration per instance.

Here is an example of how to start Exq manually:

```elixir
{:ok, sup} = Exq.start_link
```

To connect with custom configuration options (if you need multiple instances of Exq for example), you can pass in options
under start_link:

```elixir
{:ok, sup} = Exq.start_link([host: '127.0.0.1', port: 6379, namespace: 'x'])
```

By default, Exq will register itself under the ```:exq``` atom.  You can change this by passing in a name parameter:

```elixir
{:ok, exq} = Exq.start_link(name: :exq_custom)
```

### Standalone Exq:

You can run Exq standalone from the command line, to run it:

```
> mix exq.run
```

## Workers


### Enqueuing jobs:

To enqueue jobs:

```elixir
{:ok, ack} = Exq.enqueue(:exq, "default", "MyWorker", ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(:exq, "default", "MyWorker/custom_method", [])
```

You can also enqueue jobs without starting workers:

```elixir
{:ok, sup} = Exq.Enqueuer.start_link([port: 6379])

{:ok, ack} = Exq.Enqueuer.enqueue(:exq_enqueuer, "default", "MyWorker", [])

```

### Creating Workers:

To create a worker, create an elixir module matching the worker name that will be
enqueued.  To process a job with "MyWorker", create a MyWorker module.  Note that the perform also needs to
match the number of arguments as well.

Here is an example of a worker:


```elixir
defmodule MyWorker do
  def perform do
    # will get called if no custom method passed in
  end
end
```

We could enqueue a job to this worker:
```elixir
{:ok, jid} = Exq.enqueue(:exq, "default", "MyWorker", [])
```

By default, the `perform` method will be called.  However, you can pass a method such as `MyWorker/custom_method`

Example Worker:
```elixir
defmodule MyWorker do
  def custom_method(arg1) do
    # will get called since job has  "/custom_method" postfix
    # Not that arity must match args
  end
end
```

Which can be enqueued by:
```elixir
{:ok, jid} = Exq.enqueue(exq, "default", "MyWorker/custom_method", [])
```



## Web UI:

Exq comes with a Web UI to monitor your workers:

![Screenshot](http://i.imgur.com/m57gRPY.png)

To start the web UI:
```
> mix exq.ui
```

You can also use [Plug](https://github.com/elixir-lang/plug) to connect the web UI to your Web application.

## Contributions

Contributions are welcome.  Make sure to run ```mix test --no-start``` to ensure your changes have not caused any regressions.


## Contributors:

Justin McNally (j-mcnally) (structtv)

Mike Lawlor (disbelief)

Roman Smirnov (romul)

Rob Gilson (D1plo1d)

Benjamin Tan Wei Hao (benjamintanweihao)


