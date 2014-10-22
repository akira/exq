# Exq

[![Build Status](https://travis-ci.org/akira/exq.png)](https://travis-ci.org/akira/exq)

Exq is a job processing library compatible with Resque / Sidekiq for the [Elixir](http://elixir-lang.org) language.

## Example Usage:

Start process with:

```elixir
{:ok, pid} = Exq.start

# Or with config (see source for all options)
{:ok, pid} = Exq.start([host: '127.0.0.1', port: 6379, namespace: 'x'])
```

To enqueue jobs:

```elixir
{:ok, ack} = Exq.enqueue(pid, "default", "MyWorker", ["arg1", "arg2"])

{:ok, ack} = Exq.enqueue(pid, "default", "MyWorker/custom_method", [])
```

By default, the `perform` method will be called.  However, you can pass a method such as `MyWorker/custom_method`

Example Worker:
```elixir
defmodule MyWorker do
  def perform do
    # will get called if no custom method passed in
  end
end
```

## Contributors:

Benjamin Tan Wei Hao (benjamintanweihao)

Justin McNally (j-mcnally) (structtv)
