defmodule StreamServer.GRPC.EchoServiceHandler do
  @moduledoc """
  gRPC service for streaming data.
  """
  use GRPC.Server, service: Stream.EchoServer.Service
  alias Stream.HelloRequest
  alias Stream.HelloReply

  def say_server_hello(request, stream) do
    GrpcStream.from(request)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
  end

  def say_bid_stream_hello(request, stream) do
    GrpcStream.from(request)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GrpcStream.materialize(stream)
  end
end
