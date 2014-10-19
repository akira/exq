defmodule Exq.Manager do 
  use GenServer
  require Record
  Record.defrecord :state, State, [:redis, :busy_workers, :namespace, :queues, :poll_timeout]
  
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
    my_state = state(redis: redis, 
                      busy_workers: [], 
                      namespace: namespace, 
                      queues: queues, 
                      poll_timeout: poll_timeout)
    {:ok, my_state}
  end

  def handle_call({:enqueue, queue, worker, args}, _from, my_state) do 
    jid = Exq.RedisQueue.enqueue(state(my_state, :redis), state(my_state, :namespace), queue, worker, args) 
    {:reply, {:ok, jid}, my_state}
  end
  
  def handle_call({:stop}, _from, my_state) do
    { :stop, :normal, :ok, my_state }
  end
  
  def handle_info({:timeout, _ref, :poll}, my_state) do
    
    :erlang.start_timer(state(my_state, :poll_timeout), self, :poll)
    updated_state = dequeue_and_dispatch(my_state)
    {:noreply, updated_state}
  end

  def code_change(_old_version, my_state, _extra) do
    {:ok, my_state}
  end

  def terminate(_reason, _state) do 
    :ok
  end
  
  def handle_call(_request, _from, my_state) do 
    IO.puts("UKNOWN CALL")
    {:reply, :unknown, my_state}
  end  

  def handle_cast(_request, my_state) do 
    IO.puts("UKNOWN CAST")
    {:noreply, my_state}
  end  

##===========================================================
## Internal Functions
##===========================================================

  def dequeue_and_dispatch(my_state) do
    case dequeue(state(my_state, :redis), state(my_state, :namespace), state(my_state, :queues)) do 
      :none -> my_state
      job -> dispatch_job(my_state, job)
    end
  end

  def dequeue(redis, namespace, queues) do 
    Exq.RedisQueue.dequeue(redis, namespace, queues) 
  end 

  def dispatch_job(my_state, job) do 
    {:ok, worker} = Exq.Worker.start(job)
    Exq.Worker.work(worker)
    my_state
  end

  def stop(pid) do 
  end
end
