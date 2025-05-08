defmodule StreamServer.GRPC.EchoServiceHandler do
  @moduledoc """
  gRPC service for streaming data.
  """
  use GRPC.Server, service: Stream.EchoServer.Service
  alias Stream.HelloRequest
  alias Stream.HelloReply

  @spec say_unary_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_unary_hello(request, stream) do
    GrpcStream.from(request, unary: true)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "[echo] #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
  end

  @spec say_server_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_server_hello(request, stream) do
    GrpcStream.from(request)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      IO.inspect(hello, label: "Processing incoming message")
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
