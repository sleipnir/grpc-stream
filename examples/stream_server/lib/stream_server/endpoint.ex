defmodule StreamServer.Endpoint do
  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger)
  run(StreamServer.GRPC.EchoServiceHandler)
  run(StreamServer.GRPC.ReflectionServer)
end
