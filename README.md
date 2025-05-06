# GrpcStream

**Backpressure-enabled gRPC streaming adapter for Elixir using GenStage and Flow**

`GrpcStream` is an Elixir module designed to simplify gRPC server-side streaming by transforming incoming gRPC streams into `Flow` pipelines, offering backpressure and integration with additional unbounded producers (e.g., RabbitMQ, Kafka, or other `GenStage` producer).

## ✨ Features

- Convert gRPC streaming requests into `Flow` pipelines.
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

  def route_chat(req_enum, stream) do
    GrpcStream.from(req_enum, max_demand: 10)
    |> Flow.map(fn note ->
      # Process incoming gRPC message
      %MyProto.Note{message: "[echo] #{note.message}"}
    end)
    |> GrpcStream.materialize(stream)

    stream
  end
end
``` 

## 🔁 Using an External Unbounded Producer

You can enhance the stream by passing an unbounded GenStage producer (like RabbitMQ, Kafka consumer or any else GenStage producer):

```elixir
defmodule MyGRPCService do
  use GRPC.Server, service: MyService.Service
  alias GrpcStream

  def stream_events(req_enum, stream) do
    {:ok, rabbit_producer} = MyApp.RabbitMQ.Producer.start_link([])

    GrpcStream.from(req_enum, unbounded_sink_pid: rabbit_producer, max_demand: 10)
    |> Flow.map(&transform_event/1)
    |> GrpcStream.materialize(stream)

    stream
  end

  defp transform_event({_, grpc_msg}), do: grpc_msg
  defp transform_event(event), do: %MyProto.Event{data: inspect(event)}
end
```