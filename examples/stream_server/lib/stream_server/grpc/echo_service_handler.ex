defmodule StreamServer.GRPC.EchoServiceHandler do
  @moduledoc """
  gRPC service for streaming data.
  """
  use GRPC.Server, service: Stream.EchoServer.Service

  alias Stream.HelloRequest
  alias Stream.HelloReply
  alias StreamServer.TransformerServer

  @spec say_unary_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_unary_hello(request, stream) do
    GrpcStream.from(request, unary: true)
    |> GrpcStream.ask(TransformerServer)
    |> GrpcStream.map(fn %HelloReply{} = reply ->
      %HelloReply{message: "[Reply] #{reply.message}"}
    end)
    |> GrpcStream.run_with(stream)
  end

  @spec say_server_hello(HelloRequest.t(), GRPC.Server.Stream.t()) :: any()
  def say_server_hello(request, stream) do
    # simulate a infinite stream of data
    # this is a simple example, in a real world application
    # you would probably use a GenStage or similar
    # to handle the stream of data
    output_stream =
      Stream.repeatedly(fn ->
        index = :rand.uniform(10)
        %HelloReply{message: "[#{index}] I'm the Server ;)"}
      end)

    GrpcStream.from(request, join_with: output_stream)
    |> GrpcStream.map(fn
      %HelloRequest{} = hello ->
        %HelloReply{message: "Welcome #{hello.name}"}

      output_item ->
        output_item
    end)
    |> GrpcStream.run_with(stream)
  end

  @spec say_bid_stream_hello(Enumerable.t(), GRPC.Server.Stream.t()) :: any()
  def say_bid_stream_hello(request, stream) do
    GrpcStream.from(request, max_demand: 12500)
    |> GrpcStream.map(fn %HelloRequest{} = hello ->
      %HelloReply{message: "Welcome #{hello.name}"}
    end)
    |> GrpcStream.run_with(stream)
  end
end
