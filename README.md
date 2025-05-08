# GrpcStream

**Backpressure-enabled gRPC streaming adapter for Elixir using GenStage and GrpcStream**

`GrpcStream` is an Elixir module designed to simplify gRPC server-side streaming by transforming incoming gRPC streams into `GrpcStream` pipelines, offering backpressure and integration with additional unbounded producers (e.g., RabbitMQ, Kafka, or other `GenStage` producer).

## ✨ Features

- Convert gRPC streaming requests into `GrpcStream` pipelines.
- Full support for GenStage backpressure.
- Plug in additional unbounded `GenStage` producers for infinite/event-driven streaming.
- Send processed messages back to clients via gRPC streams.

---


## 🚀 Installation

Add the dependencies to your `mix.exs` file:

```elixir
def deps do
  [
    {:grpc_stream, github: "sleipnir/grpc_stream"},
  ]
end
```

## ⚙️ Basic Usage

```elixir
defmodule MyGRPCService do
  use GRPC.Server, service: MyService.Service
  alias GrpcStream

  def route_chat(request, materializer) do
    GrpcStream.from(request, max_demand: 10)
    |> GrpcStream.map(fn note ->
      # Process incoming gRPC message
      %MyProto.Note{message: "[echo] #{note.message}"}
    end)
    |> GrpcStream.run_with(materializer)
  end
end
``` 

## 🔁 Using an External Unbounded Producer

You can enhance the stream by passing an unbounded GenStage producer (like RabbitMQ, Kafka consumer or any else GenStage producer):

```elixir
defmodule MyGRPCService do
  use GRPC.Server, service: MyService.Service
  alias GrpcStream

  def stream_events(request, materializer) do
    {:ok, rabbit_producer} = MyApp.RabbitMQ.Producer.start_link([])

    GrpcStream.from(request, join_with: rabbit_producer, max_demand: 10)
    |> GrpcStream.map(&transform_event/1)
    |> GrpcStream.run_with(materializer)
  end

  defp transform_event({_, grpc_msg}), do: grpc_msg
  defp transform_event(event), do: %MyProto.Event{data: inspect(event)}
end
```

## 📡 Synchronous Request-Response with Processes
Use ask/3 to implement request-response patterns with arbitrary processes:

```elixir
defmodule ChatHandler do
  def start do
    spawn(fn -> 
      receive do
        {:request, msg, from} -> 
          processed = "[ECHO] #{msg}"
          send(from, {:response, processed})
      end
    end)
  end
end

defmodule MyGRPCService do
  use GRPC.Server, service: Chat.Service
  
  def chat_stream(req_enum, materializer) do
    handler_pid = ChatHandler.start()
    
    GrpcStream.from(req_enum)
    |> GrpcStream.ask(handler_pid)
    |> GrpcStream.map(fn
      {:error, :timeout} -> %ChatMsg{text: "Server timeout!"}
      response -> %ChatMsg{text: response}
    end)
    |> GrpcStream.run_with(materializer)
  end
end
```

## 🏗️ Using GenServer for Backend Processing
For more robust interactions, use the GenServer version with registered modules:

```elixir
defmodule AnalyticsServer do
  use GenServer
  
  def start_link(), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  
  # GenServer implementation
  def handle_call({:request, event}, _from, state) do
    processed_event = process_analytics(event)
    {:reply, {:response, processed_event}, state}
  end
  
  defp process_analytics(event), do: # ... analytics logic ...
end

defmodule MyGRPCService do
  use GRPC.Server, service: Analytics.Service
  
  @spec event_stream(any(), GRPC.Server.Stream.t()) :: any()
  def event_stream(request, materializer) do
    AnalyticsServer.start_link()
    
    GrpcStream.from(request)
    |> GrpcStream.ask(AnalyticsServer, 10_000)
    |> GrpcStream.map(fn
      {:error, :timeout} -> %AnalyticEvent{status: :TIMEOUT}
      result -> %AnalyticEvent{data: result}
    end)
    |> GrpcStream.run_with(materializer)
  end
end
```

## 🛠️ Hybrid Example with External Producer
Combine with external systems while maintaining request-response semantics:

```elixir
defmodule TransactionService do
  use GenServer
  
  def handle_call({:request, tx}, _from, state) do
    {:reply, {:response, validate_transaction(tx)}, state}
  end
  
  defp validate_transaction(tx) do
    :timer.sleep(500)
    %TransactionResult{valid: true}
  end
end

defmodule MyGRPCService do
  use GRPC.Server, service: Transaction.Service
  
  def process_transactions(request, materializer) do
    {:ok, kafka_producer} = MyApp.KafkaProducer.start_link()
    TransactionService.start_link() # or start in another place
    
    GrpcStream.from(req_enum, 
      join_with: kafka_producer,
      max_demand: 20
    )
    |> GrpcStream.ask(TransactionService) # Validate via GenServer
    |> GrpcStream.filter(fn
      %TransactionResult{valid: true} -> true
      _ -> false
    end)
    |> GrpcStream.run_with(materializer)
  end
end
``` 

See more in [tests](./test/grpc_stream_test.exs)