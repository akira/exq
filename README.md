# Exq

[![Build Status](https://travis-ci.org/akira/exq.png?branch=master)](https://travis-ci.org/akira/exq?branch=master)

Exq is a job processing library compatible with Resque / Sidekiq for the [Elixir](http://elixir-lang.org) language.

## Example Usage:

Start process with:

```elixir
{:ok, pid} = Exq.start_link

# Or with config (see source for all options)
{:ok, pid} = Exq.start_link([host: '127.0.0.1', port: 6379, namespace: 'x'])
```

To enqueue jobs:

```elixir
{:ok, ack} = Exq.enqueue(pid, "default", "MyWorker", ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(pid, "default", "MyWorker/custom_method", [])
```

You can also enqueue jobs without starting workers:

```elixir
{:ok, enq} = Exq.Enqueuer.start_link([port: 6555])

{:ok, ack} = Exq.Enqueuer.enqueue(enq, "default", "MyWorker", [])

```

Example Worker:
```elixir
defmodule MyWorker do
  def perform do
    # will get called if no custom method passed in
  end
end
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


## Contributors:

Justin McNally (j-mcnally) (structtv)

Benjamin Tan Wei Hao (benjamintanweihao)


