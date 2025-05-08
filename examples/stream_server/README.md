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

  @spec say_unary_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_unary_hello(request, stream) do
    GrpcStream.from(request)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "[echo] #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
  end

  @spec say_server_hello(Enumerable.t(), GRPC.Server.Stream.t()) :: any()
  def say_server_hello(request, stream) do
    GrpcStream.from(request)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
  end

  @spec say_bid_stream_hello(Elixir.Stream.t(), GRPC.Server.Stream.t()) :: any()
  def say_bid_stream_hello(request, stream) do
    GrpcStream.from(request, max_demand: 12500)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
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