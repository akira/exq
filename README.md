# Exq

[![Travis Build Status](https://img.shields.io/travis/akira/exq.svg)](https://travis-ci.org/akira/exq)
[![Coveralls Coverage](https://img.shields.io/coveralls/akira/exq.svg)](https://coveralls.io/github/akira/exq)
[![Hex.pm Version](https://img.shields.io/hexpm/v/exq.svg)](https://hex.pm/packages/exq)

Exq is a job processing library compatible with Resque / Sidekiq for the [Elixir](http://elixir-lang.org) language.
* Exq uses Redis as a store for background processing jobs.
* Exq handles concurrency, job persistence, job retries, and tracking so you don't have to.
* Jobs are persistent so they would survive across node restarts.
* You can use multiple Erlang nodes to process from the same pool of jobs.
* Exq uses a format that is Resque/Sidekiq compatible.
  * This means you can use it to integrate with existing Rails / Django projects that also use a background job that's Resque compatible - typically with little or no changes needed to your existing apps. However, you can also use Exq standalone.
  * If you don't need Resque/Sidekiq compatibility, another option to check out would be [toniq](https://github.com/joakimk/toniq) which uses erlang serialization instead of JSON.
  * You can run both Exq and Toniq in the same app for different workers.
* Exq supports uncapped amount of jobs running, or also allows a max limit per queue.
* Exq supports job retries with exponential backoff.
* Exq tracks several stats including failed busy, and processed jobs.
* Exq provides an optional web UI that you can use to view several stats as well as rate of job processing.

## Getting Started:

This assumes you have an instance of [Redis](http://redis.io/) to use.

### Installation:
Add exq to your mix.exs deps (replace version with the latest hex.pm package version):

```elixir
  defp deps do
    [
      # ... other deps
      {:exq, "~> 0.4.2"}
    ]
  end
```

Then run ```mix deps.get```.

### Configuration:

By default, Exq will use configuration from your config.exs file.  You can use this
to configure your Redis host, port, password, as well as namespace (which helps isolate the data in Redis).
The "concurrency" setting will let you configure the amount of concurrent workers that will be allowed, or :infinite to disable any throttling.

```elixir
config :exq,
  host: "127.0.0.1",
  port: 6379,
  password: "optional_redis_auth",
  namespace: "exq",
  concurrency: :infinite,
  queues: ["default"],
  poll_timeout: 50,
  scheduler_poll_timeout: 200,
  scheduler_enable: true,
  max_retries: 25
```

### Concurrency:

Exq supports concurrency setting per queue.  You can specify the same ```concurrency``` option to apply to each queue or specify it based on a per queue basis.

Concurrency for each queue will be set at ```1000```:

```elixir
config :exq,
  host: "127.0.0.1",
  port: 6379,
  namespace: "exq",
  concurrency: 1000,
  queues: ["default"]
```

Concurrency for ```q1``` is set at ```10_000``` while ```q2``` is set at ```10```:

```elixir
config :exq,
  host: "127.0.0.1",
  port: 6379,
  namespace: "exq",
  queues: [{"q1", 10_000}, {"q2", 10}]
```


### Job Retries:

Exq will automatically retry failed job. It will use an exponential backoff timing similar to Sidekiq or delayed_job to retry failed jobs. It can be configured via these settings:

```elixir
config :exq,
  host: "127.0.0.1",
  port: 6379,
  ...
  scheduler_enable: true,
  max_retries: 25
```

Note that ```scheduler_enable``` has to be set to ```true``` and ```max_retries``` should be greater than ```0```.


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

## Using iex:
If you'd like to try Exq out on the iex console, you can do this by typing ```iex -S mix``` after ```mix deps.get```.

### Standalone Exq:

You can run Exq standalone from the command line, to run it:

```
> mix exq.run
```

## Workers


### Enqueuing jobs:

To enqueue jobs:

```elixir
{:ok, ack} = Exq.enqueue(:exq, "default", MyWorker, ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(:exq, "default", "MyWorker", ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(:exq, "default", "MyWorker/custom_method", [])
```

You can also enqueue jobs without starting workers:

```elixir
{:ok, sup} = Exq.Enqueuer.start_link([port: 6379])

{:ok, ack} = Exq.Enqueuer.enqueue(:exq_enqueuer, "default", MyWorker, [])

```
You can also schedule jobs to start at a future time:
You need to make sure scheduler_enable is set to true

Schedule a job to start in 5 mins
```elixir
{:ok, ack} = Exq.enqueue_in(:exq, "default", 300, MyWorker, ["arg1", "arg2"])
```
Schedule a job to start at 8am 2015-12-25 UTC
```elixir
time = Timex.Date.from({{2015, 12, 25}, {8, 0, 0}}) |> Timex.Date.to_timestamp
{:ok, ack} = Exq.enqueue_at(:exq, "default", time, MyWorker, ["arg1", "arg2"])
```

### Dynamic queue subscriptions:

The list of queues that are being monitored by Exq is determined by the config.exs file or the parameters passed to Exq.start.  However, we can also dynamically add and remove queue subscriptions after exq has started.

To subscribe to a new queue:
```elixir
# last arg is optional and is the max concurrency for the queue
:ok = Exq.subscribe(:exq, "new_queue_name", 10)
```

To unsubscribe from a queue:
```elixir
:ok = Exq.unsubscribe(:exq, "queue_to_unsubscribe")
```

### Creating Workers:

To create a worker, create an elixir module matching the worker name that will be
enqueued.  To process a job with "MyWorker", create a MyWorker module.  Note that the perform also needs to
match the number of arguments as well.

Here is an example of a worker:


```elixir
defmodule MyWorker do
  def perform do
  end
end
```

We could enqueue a job to this worker:
```elixir
{:ok, jid} = Exq.enqueue(:exq, "default", MyWorker, [])
```

The 'perform' method will be called with matching args. For example:
```elixir
{:ok, jid} = Exq.enqueue(exq, "default", "MyWorker", [arg1, arg2])
```

Would match:
```elixir
defmodule MyWorker do
  def perform(arg1, arg2) do
  end
end
```

## Security

By default, you Redis server could be open to the world. As by default, Redis comes with no password authentication, and some hosting companies leave that port accessible to the world.. This means that anyone can read data on the queue as well as pass data in to be run. Obviously this is not desired, please secure your Redis installation by following guides such as the [Digital Ocean Redis Security Guide](https://www.digitalocean.com/community/tutorials/how-to-secure-your-redis-installation-on-ubuntu-14-04).


## Web UI:

Exq comes with a Web UI to monitor your workers:

![Screenshot](http://i.imgur.com/m57gRPY.png)

To start the web UI:
```
> mix exq.ui
```

You can also use [Plug](https://github.com/elixir-lang/plug) to connect the web UI to your Web application.

## Starting Exq manually:

Typically, Exq will start as part of the application along with the configuration you have set.  However, you can also start Exq manually and set your own configuration per instance.

Here is an example of how to start Exq manually:

```elixir
{:ok, sup} = Exq.start_link
```

To connect with custom configuration options (if you need multiple instances of Exq for example), you can pass in options
under start_link:

```elixir
{:ok, sup} = Exq.start_link([host: "127.0.0.1", port: 6379, namespace: "x"])
```

By default, Exq will register itself under the ```:exq``` atom.  You can change this by passing in a name parameter:

```elixir
{:ok, exq} = Exq.start_link(name: :exq_custom)
```

## Contributions

Contributions are welcome. Tests are encouraged.

To run tests / ensure your changes have not caused any regressions:

```
redis-server --port 6555
mix test
```

## Contributors:

Justin McNally (j-mcnally) (structtv)

Nick Sanders (nicksanders)

Nick Gal (nickgal)

Mike Lawlor (disbelief)

Udo Kramer (optikfluffel)

Andreas Franzén (triptec)

Daniel Perez (tuvistavie)

David Le (dl103)

Roman Smirnov (romul)

akki91 (Akshay)

Rob Gilson (D1plo1d)

Benjamin Tan Wei Hao (benjamintanweihao)
