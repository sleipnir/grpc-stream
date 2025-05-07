defmodule StreamServer.GRPC.ReflectionServer do
  @moduledoc """
  gRPC reflection server.
  """
  use GrpcReflection.Server,
    version: :v1,
    services: [Stream.EchoServer.Service]
end
