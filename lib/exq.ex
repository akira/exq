defmodule Exq do
  use GenServer.Behaviour
  
  defrecord State, [:redis, :busy_workers, :namespace, :queues, :poll_timeout]
  
  def start(opts // []) do 
    :gen_server.start(__MODULE__, opts, [])
  end

  def stop(pid) do
    :gen_server.call(pid, {:stop})
  end

  def enqueue(pid, queue, worker, args) do 
    :gen_server.call(pid, {:enqueue, queue, worker, args})
  end
 
  #TODO: start with exploded and validated options
  #def start(...)

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do 
    host = Keyword.get(opts, :host, '127.0.0.1') 
    port = Keyword.get(opts, :port, 6379) 
    database = Keyword.get(opts, :database, 0)
    password = Keyword.get(opts, :password, '') 
    queues = Keyword.get(opts, :queues, ["default"]) 
    namespace = Keyword.get(opts, :namespace, "resque")
    poll_timeout = Keyword.get(opts, :poll_timeout, 100)
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, 100)
    {:ok, redis} = :eredis.start_link(host, port, database, password, reconnect_on_sleep)
    :erlang.start_timer(0, self, :poll) 
    {:ok, State.new(redis: redis, busy_workers: [], namespace: namespace, queues: queues, poll_timeout: poll_timeout)}
  end

  def handle_call({:enqueue, queue, worker, args}, _from, state) do 
    jid = Exq.RedisQueue.enqueue(state.redis, state.namespace, queue, worker, args) 
    {:reply, {:ok, jid}, state}
  end
  
  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end
  
  def handle_info({:timeout, _ref, :poll}, state) do
    :erlang.start_timer(state.poll_timeout, self, :poll)
    dequeue(state)
    {:noreply, state}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do 
    :ok
  end
  
  def handle_call(_request, _from, state) do 
    IO.puts("UKNOWN CALL")
    {:reply, :unknown, state}
  end  

  def handle_cast(_request, state) do 
    IO.puts("UKNOWN CAST")
    {:noreply, state}
  end  

##===========================================================
## Internal Functions
##===========================================================
 
  def dequeue(state) do 
    case Exq.RedisQueue.dequeue(state.redis, state.namespace, state.queues) do 
      :none -> IO.puts("DEQUEUED EMPTY")
      job -> IO.puts("GOT #{job}")
    end
  end 

  def stop(pid) do 
  end
end
