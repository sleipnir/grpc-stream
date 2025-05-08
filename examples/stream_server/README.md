# gRPC Stream Server

## Contract definition and Coding

1. Build protobufs:

```protobuf
syntax = "proto3";

package stream;

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}

service EchoServer {
  rpc SayUnaryHello (HelloRequest) returns (HelloReply) {}
  rpc SayServerHello (HelloRequest) returns (stream HelloReply) {}
  rpc SayBidStreamHello (stream HelloRequest) returns (stream HelloReply) {}
}
```

2. Write elixir code:
```elixir
defmodule StreamServer.GRPC.EchoServiceHandler do
  @moduledoc """
  gRPC service for streaming data.
  """
  use GRPC.Server, service: Stream.EchoServer.Service

  alias Stream.HelloRequest
  alias Stream.HelloReply
  alias StreamServer.TransformerServer

  @spec say_unary_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_unary_hello(request, materializer) do
    GRPCStream.from(request, unary: true)
    |> GRPCStream.ask(TransformerServer) # call GenServer and get response
    |> GRPCStream.map(fn %HelloReply{} = reply ->
      %HelloReply{message: "[Reply] #{reply.message}"}
    end)
    |> GRPCStream.run_with(materializer)
  end

  @spec say_server_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_server_hello(request, materializer) do
    # simulate a infinite stream of data
    # this is a simple example, in a real world application
    # you would probably use a GenStage or similar
    # to handle the stream of data
    output_stream =
      Stream.repeatedly(fn ->
        index = :rand.uniform(10)
        %HelloReply{message: "[#{index}] I'm the Server ;)"}
      end)

    GRPCStream.from(request, join_with: output_stream)
    |> GRPCStream.map(fn
      %HelloRequest{} = hello ->
        %HelloReply{message: "Welcome #{hello.name}"}

      output_item ->
        output_item
    end)
    |> GRPCStream.run_with(materializer)
  end

  @spec say_bid_stream_hello(Elixir.Stream.t(), GRPC.Server.Stream.t()) :: any()
  def say_bid_stream_hello(request, materializer) do
    GRPCStream.from(request, max_demand: 12500)
    |> GRPCStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GRPCStream.run_with(materializer)
  end
end
```

## Start gRPC Server

```bash
iex -S mix
``` 

## Send unary request

```bash
grpcurl -plaintext -d '{"name": "Joe"}' localhost:50051 stream.EchoServer/SayUnaryHello
``` 

## Send Server stream request

```bash
grpcurl -plaintext -d '{"name": "Valim"}' localhost:50051 stream.EchoServer/SayServerHello
``` 

## Send Streamed request

1. Generate fake data
```bash
./generate_data.sh
``` 

2. Make request
```bash
cat bulk_input.json | grpcurl -plaintext -d @ localhost:50051 stream.EchoServer/SayBidStreamHello
``` 