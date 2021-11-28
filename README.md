# Exq

[![CI](https://github.com/akira/exq/actions/workflows/ci.yml/badge.svg)](https://github.com/akira/exq/actions/workflows/ci.yml)
[![Coveralls Coverage](https://img.shields.io/coveralls/akira/exq.svg)](https://coveralls.io/github/akira/exq)
[![Module Version](https://img.shields.io/hexpm/v/exq.svg)](https://hex.pm/packages/exq)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/exq/)
[![Total Download](https://img.shields.io/hexpm/dt/exq.svg)](https://hex.pm/packages/exq)
[![License](https://img.shields.io/hexpm/l/exq.svg)](https://github.com/akira/exq/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/akira/exq.svg)](https://github.com/akira/exq/commits/master)

Exq is a job processing library compatible with Resque / Sidekiq for the [Elixir](http://elixir-lang.org) language.
* Exq uses Redis as a store for background processing jobs.
* Exq handles concurrency, job persistence, job retries, reliable queueing and tracking so you don't have to.
* Jobs are persistent so they would survive across node restarts.
* You can use multiple Erlang nodes to process from the same pool of jobs.
* Exq uses a format that is Resque/Sidekiq compatible.
  * This means you can use it to integrate with existing Rails / Django projects that also use a background job that's Resque compatible - typically with little or no changes needed to your existing apps. However, you can also use Exq standalone.
  * You can also use the Sidekiq UI to view job statuses, as Exq is compatible with the Sidekiq stats format.
  * If you don't need Resque/Sidekiq compatibility, another option to check out would be [toniq](https://github.com/joakimk/toniq) which uses erlang serialization instead of JSON.
  * You can run both Exq and Toniq in the same app for different workers.
* Exq supports uncapped amount of jobs running, or also allows a max limit per queue.
* Exq supports job retries with exponential backoff.
* Exq supports configurable middleware for customization / plugins.
* Exq tracks several stats including failed busy, and processed jobs.
* Exq stores in progress jobs in a backup queue (using the Redis RPOPLPUSH command).
  This means that if the system or worker is restarted while a job is in progress,
  the job will be re_enqueued when the node is restarted and not lost.
* Exq provides an optional web UI that you can use to view several stats as well as rate of job processing.
* When shutting down Exq will attempt to let workers terminate gracefully,
  with a configurable timeout.
* There is no time limit to how long a job can run for.

### Do you need Exq?

While you may reach for Sidekiq / Resque / Celery by default when writing apps in other languages, in Elixir there are some good options to consider that are already provided by the language and platform. So before adding Exq or any Redis backed queueing library to your application, make sure to get familiar with OTP and see if that is enough for your needs. Redis backed queueing libraries do add additional infrastructure complexity and also overhead due to serialization / marshalling, so make sure to evaluate whether it is an actual need or not.

Some OTP related documentation to look at:

* GenServer: http://elixir-lang.org/getting-started/mix-otp/genserver.html
* Task: https://hexdocs.pm/elixir/Task.html
* GenStage: https://hexdocs.pm/gen_stage/GenStage.html
* Supervisor: http://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html
* OTP: http://erlang.org/doc/

If you need a durable jobs, retries with exponential backoffs, dynamically scheduled jobs in the future - that are all able to survive application restarts, then an externally backed queueing library such as Exq could be a good fit.

If you are starting a brand new project, I would also take a look at [Faktory](https://github.com/contribsys/faktory). It provides language independent queueing system, which means this logic doesn't have to be implemented across different languages and can use a thin client such as [faktory_worker_ex](https://github.com/cjbottaro/faktory_worker_ex).

## Getting Started

### Pre-requisite

This assumes you have an instance of [Redis](http://redis.io/) to use.  The easiest way to install it on OSX is via brew:

```
> brew install redis
```
To start it:
```
> redis-server
```

### Screencast on elixircasts.io:

If you prefer video instructions, check out the screencast on elixircasts.io which details how to install and use the Exq library:
https://elixircasts.io/elixir-job-processing-with-exq

### Installation
Add `:exq` to your `mix.exs` deps (replace version with the latest hex.pm package version):

```elixir
defp deps do
  [
    # ... other deps
    {:exq, "~> 0.15.0"}
  ]
end
```

Then run ```mix deps.get```.


### Configuration

By default, Exq will use configuration from your config.exs file.  You can use this to configure your Redis host, port, password, as well as namespace (which helps isolate the data in Redis). If you would like to specify your options as a Redis URL, that is also an option using the `url` config key (in which case you would not need to pass the other Redis options).

Configuration options may optionally be given in the `{:system, "VARNAME"}` format, which will resolve to the runtime environment value.

Other options include:
* The `queues` list specifies which queues Exq will listen to for new jobs.
* The `concurrency` setting will let you configure the amount of concurrent workers that will be allowed, or :infinite to disable any throttling.
* The `name` option allows you to customize Exq's registered name, similar to using `Exq.start_link([name: Name])`. The default is Exq.
* If the option `start_on_application` is `false`, Exq won't be started automatically when booting up you Application. You can start it with `Exq.start_link/1`.
* The `shutdown_timeout` is the number of milliseconds to wait for workers to
  finish processing jobs when the application is shutting down. It defaults to
  5000 ms.
* The `mode` option can be used to control what components of Exq are started. This would be useful if you want to only enqueue jobs in one node and run the workers in different node.
  * `:default` - starts worker, enqueuer and API.
  * `:enqueuer` - starts only the enqueuer.
  * `:api` - starts only the api.
  * `[:api, :enqueuer]` - starts both enqueuer and api.
* The `backoff` option allows you to customize the backoff time used for retry when a job fails. By default exponential time scaled based on job's retry_count is used. To change the default behavior, create a new module which implements the `Exq.Backoff.Behaviour` and set backoff option value to the module name.

```elixir
config :exq,
  name: Exq,
  host: "127.0.0.1",
  port: 6379,
  password: "optional_redis_auth",
  namespace: "exq",
  concurrency: :infinite,
  queues: ["default"],
  poll_timeout: 50,
  scheduler_poll_timeout: 200,
  scheduler_enable: true,
  max_retries: 25,
  mode: :default,
  shutdown_timeout: 5000
```

### Concurrency

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


### Job Retries

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

### Dead Jobs

Any job that has failed more than ```max_retries``` times will be
moved to dead jobs queue. Dead jobs could be manually re-enqueued via
Sidekiq UI. Max size and timeout of dead jobs queue can be configured via
these settings:

```elixir
config :exq,
  dead_max_jobs: 10_000,
  dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
```


### OTP Application

You can add Exq into your OTP application list, and it will start an instance of Exq along with your application startup.  It will use the configuration from your ```config.exs``` file.

```elixir
def application do
  [
    applications: [:logger, :exq],
    #other stuff...
  ]
end
```

When using Exq through OTP, it will register a process under the name ```Elixir.Exq``` - you can use this atom where expecting a process name in the Exq module.

If you would like to control Exq startup, you can configure Exq to not start anything on application start. For example, if you are using Exq along with Phoenix, and your workers are accessing the database or other resources, it is recommended to disable Exq startup and manually add it to the supervision tree.

This can be done by setting `start_on_application` to false and adding it to your supervision tree:

```elixir
config :exq,
   start_on_application: false
```

```elixir
def start(_type, _args) do
  children = [
    # Start the Ecto repository
    MyApp.Repo,
    # Start the endpoint when the application starts
    MyApp.Endpoint,
    # Start the EXQ supervisor
    Exq,
  ]
```

### Sentinel

Exq uses [Redix](https://github.com/whatyouhide/redix) client for
communication with redis server. The client can be configured to use
sentinel via `redis_options`. Note: you need to have Redix 0.9.0+.

```elixir
config :exq
  redis_options: [
    sentinel: [sentinels: [[host: "127.0.0.1", port: 6666]], group: "exq"],
    database: 0,
    password: nil,
    timeout: 5000,
    name: Exq.Redis.Client,
    socket_opts: []
  ]
```


## Using IEx

If you'd like to try Exq out on the iex console, you can do this by typing:

```bash
> mix deps.get
```

and then:

```bash
> iex -S mix
```

### Standalone Exq

You can run Exq standalone from the command line, to run it:

```bash
> mix do app.start, exq.run
```

## Workers

### Enqueuing jobs:

To enqueue jobs:

```elixir
{:ok, ack} = Exq.enqueue(Exq, "default", MyWorker, ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(Exq, "default", "MyWorker", ["arg1", "arg2"])

## Don't retry job in per worker
{:ok, ack} = Exq.enqueue(Exq, "default", MyWorker, ["arg1", "arg2"], max_retries: 0)
## max_retries = 10, it will override :max_retries in config
{:ok, ack} = Exq.enqueue(Exq, "default", MyWorker, ["arg1", "arg2"], max_retries: 10)

```
In this example, `"arg1"` will get passed as the first argument to the `perform` method in your worker, `"arg2"` will be second argument, etc.

You can also enqueue jobs without starting workers:

```elixir
{:ok, sup} = Exq.Enqueuer.start_link([port: 6379])

{:ok, ack} = Exq.Enqueuer.enqueue(Exq.Enqueuer, "default", MyWorker, [])
```

You can also schedule jobs to start at a future time. You need to make sure scheduler_enable is set to true.

Schedule a job to start in 5 mins:

```elixir
{:ok, ack} = Exq.enqueue_in(Exq, "default", 300, MyWorker, ["arg1", "arg2"])

# If using `mode: [:enqueuer]`
{:ok, ack} = Exq.Enqueuer.enqueue_in(Exq.Enqueuer, "default", 300, MyWorker, ["arg1", "arg2"])
```

Schedule a job to start at 8am 2015-12-25 UTC:

```elixir
time = Timex.now() |> Timex.shift(days: 8)
{:ok, ack} = Exq.enqueue_at(Exq, "default", time, MyWorker, ["arg1", "arg2"])

# If using `mode: [:enqueuer]`
{:ok, ack} = Exq.Enqueuer.enqueue_at(Exq.Enqueuer, "default", time, MyWorker, ["arg1", "arg2"])
```

### Creating Workers

To create a worker, create an elixir module matching the worker name that will be enqueued. To process a job with "MyWorker", create a MyWorker module.  Note that the perform also needs to match the number of arguments as well.

Here is an example of a worker:

```elixir
defmodule MyWorker do
  def perform do
  end
end
```

We could enqueue a job to this worker:

```elixir
{:ok, jid} = Exq.enqueue(Exq, "default", MyWorker, [])
```

The 'perform' method will be called with matching args. For example:

```elixir
{:ok, jid} = Exq.enqueue(Exq, "default", "MyWorker", [arg1, arg2])
```

Would match:

```elixir
defmodule MyWorker do
  def perform(arg1, arg2) do
  end
end
```

### Job data from worker

If you'd like to get Job metadata information from a worker, you can call `worker_job` from within the worker:

```elixir
defmodule MyWorker do
  def perform(arg1, arg2) do
    # get job metadata
    job = Exq.worker_job()
  end
end
```

### Dynamic queue subscriptions

The list of queues that are being monitored by Exq is determined by the ```config.exs``` file or the parameters passed to Exq.start_link.  However, we can also dynamically add and remove queue subscriptions after Exq has started.

To subscribe to a new queue:

```elixir
# last arg is optional and is the max concurrency for the queue
:ok = Exq.subscribe(Exq, "new_queue_name", 10)
```

To unsubscribe from a queue:

```elixir
:ok = Exq.unsubscribe(Exq, "queue_to_unsubscribe")
```

To unsubscribe from all queues:

```elixir
:ok = Exq.unsubscribe_all(Exq)
```

## Middleware Support

If you'd like to customize worker execution and/or create plugins like Sidekiq/Resque have, Exq supports custom middleware. The first step would be to define the middleware in ```config.exs``` and add your middleware into the chain:

```elixir
middleware: [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager,
  Exq.Middleware.Logger]
```

You can then create a module that implements the middleware behavior and defines `before_work`,  `after_processed_work` and `after_failed_work` functions.  You can also halt execution of the chain as well. For a simple example of middleware implementation, see the [Exq Logger Middleware](https://github.com/akira/exq/blob/master/lib/exq/middleware/logger.ex).

## Using with Phoenix and Ecto

If you would like to use Exq alongside Phoenix and Ecto, add `:exq` to your mix.exs application list:

```elixir
def application do
  [
    mod: {Chat, []},
    applications: [:phoenix, :phoenix_html, :cowboy, :logger, :exq]
  ]
end
```

Assuming you will be accessing the database from Exq workers, you will want to lower the concurrency level for those workers, as they are using a finite pool of connections and can potentially back up and time out. You can lower this through the ```concurrency``` setting, or perhaps use a different queue for database workers that have a lower concurrency just for that queue. Inside your worker, you would then be able to use the Repo to work with the database:

```elixir
defmodule Worker do
  def perform do
    HelloPhoenix.Repo.insert!(%HelloPhoenix.User{name: "Hello", email: "world@yours.com"})
  end
end
```

## Using alongside Sidekiq / Resque

To use alongside Sidekiq / Resque, make sure your namespaces as configured in Exq match the namespaces you are using in Sidekiq. By default, Exq will use the ```exq``` namespace, so you will have to change that.

Another option is to modify Sidekiq to use the Exq namespace in the sidekiq initializer in your ruby project:

```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://127.0.0.1:6379', namespace: 'exq' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://127.0.0.1:6379', namespace: 'exq' }
end
```

For an implementation example, see sineed's demo app illustrating  [Sidekiq to Exq communication](https://github.com/sineed/exq_sidekiq_demo_app).

If you would like to exclusively send some jobs from Sidekiq to Exq as your migration strategy, you should create queue(s) that are exclusively listened to only in Exq (and configure those in the queue section in the Exq config). Make sure they are not configured to be listened to in Sidekiq, otherwise Sidekiq will also take jobs off that queue. You can still Enqueue jobs to that queue in Sidekiq even though they are not being monitored:

```ruby
Sidekiq::Client.push('queue' => 'elixir_queue', 'class' => 'ElixirWorker', 'args' => ['foo', 'bar'])
```

## Security

By default, your Redis server could be open to the world. As by default, Redis comes with no password authentication, and some hosting companies leave that port accessible to the world.. This means that anyone can read data on the queue as well as pass data in to be run. Obviously this is not desired, please secure your Redis installation by following guides such as the [Digital Ocean Redis Security Guide](https://www.digitalocean.com/community/tutorials/how-to-secure-your-redis-installation-on-ubuntu-14-04).

## Node Recovery

A Node can be stopped unexpectedly while processing jobs due to various reasons like deployment, system crash, OOM, etc. This could leave the jobs in the in-progress state. Exq comes with two mechanisms to handle this situation.

### Same Node Recovery

Exq identifies each node using an identifier. By default machine's hostname is used as the identifier. When a node comes back online after a crash, it will first check if there are any in-progress jobs for its identifier. Note that it will only re-enqueue jobs with the same identifier. There are environments like Heroku or Kubernetes where the hostname would change on each deployment. In those cases, the default identifier can be overridden

```elixir
config :exq,
   node_identifier: MyApp.CustomNodeIdentifier
```

```elixir
defmodule MyApp.CustomNodeIdentifier do
  @behaviour Exq.NodeIdentifier.Behaviour

  def node_id do
     # return node ID, perhaps from environment variable, etc
     System.get_env("NODE_ID")
  end
end
```

### Heartbeat

Same node recovery is straightforward and works well if the number of worker nodes is fixed. There are use cases that need the worker nodes to be autoscaled based on the workload. In those situations, a node that goes down might not come back for a very long period.

Heartbeat mechanism helps in these cases. Each node registers a heartbeat at regular interval. If any node misses 5 consecutive heartbeats, it will be considered dead and all the in-progress jobs belong to that node will be re-enqueued.

This feature is disabled by default and can be enabled using the following config:j

```elixir
config :exq,
    heartbeat_enable: true,
    heartbeat_interval: 60_000,
    missed_heartbeats_allowed: 5
```

## Web UI

Exq has a separate repo, exq_ui which provides with a Web UI to monitor your workers:

![Screenshot](http://i.imgur.com/m57gRPY.png)

See https://github.com/akira/exq_ui for more details.

## Starting Exq manually

Typically, Exq will start as part of the application along with the configuration you have set.  However, you can also start Exq manually and set your own configuration per instance.

Here is an example of how to start Exq manually:

```elixir
{:ok, sup} = Exq.start_link
```

To connect with custom configuration options (if you need multiple instances of Exq for example), you can pass in options under start_link:

```elixir
{:ok, sup} = Exq.start_link([host: "127.0.0.1", port: 6379, namespace: "x"])
```

By default, Exq will register itself under the ```Elixir.Exq``` atom.  You can change this by passing in a name parameter:

```elixir
{:ok, exq} = Exq.start_link(name: Exq.Custom)
```

## Testing

`Exq.Mock` module provides few options to test your workers:

```elixir
# change queue_adapter in config/test.exs
config :exq,
  queue_adapter: Exq.Adapters.Queue.Mock

# start mock server in your test_helper.exs
Exq.Mock.start_link(mode: :redis)
```

`Exq.Mock` currently supports three modes. The default mode can provided
on the `Exq.Mock.start_link` call. The mode could be overridden for
each test by calling `Exq.Mock.set_mode(:fake)`

### redis

This could be used for integration testing. Doesn't support `async: true` option.

### fake

The jobs get enqueued in a local queue and never get executed. `Exq.Mock.jobs()` returns all the jobs. Supports `async: true` option.

### inline

The jobs get executed in the same process. Supports `async: true` option.

## Donation

To donate, send to:

Bitcoin (BTC): `17j52Veb8qRmVKVvTDijVtmRXvTUpsAWHv`
Ethereum (ETH): `0xA0add27EBdB4394E15b7d1F84D4173aDE1b5fBB3`


## Questions?  Issues?

For issues, please submit a Github issue with steps on how to reproduce the problem.


## Contributions

Contributions are welcome. Tests are encouraged.

To run tests / ensure your changes have not caused any regressions:

```
mix test --no-start
```

To run the full suite, including failure conditions (can have some false negatives):

```
mix test --trace --include failure_scenarios:true --no-start
```

## Maintainers

Anantha Kumaran / @ananthakumaran (Lead)

## Contributors

Justin McNally (j-mcnally) (structtv), zhongwencool (zhongwencool), Joe Webb (ImJoeWebb), Chelsea Robb (chelsea), Nick Sanders (nicksanders), Nick Gal (nickgal), Ben Wilson (benwilson512), Mike Lawlor (disbelief), colbyh (colbyh), Udo Kramer (optikfluffel), Andreas Franzén (triptec),Josh Kalderimis (joshk), Daniel Perez (tuvistavie), Victor Rodrigues (rodrigues), Denis Tataurov (sineed), Joe Honzawa (Joe-noh), Aaron Jensen (aaronjensen), Andrew Vy (andrewvy), David Le (dl103), Roman Smirnov (romul), Thomas Athanas (typicalpixel), Wen Li (wli0503), Akshay (akki91), Rob Gilson (D1plo1d), edmz (edmz), and Benjamin Tan Wei Hao (benjamintanweihao).

## Copyright and License

Copyright (c) 2014 Alex Kira

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
