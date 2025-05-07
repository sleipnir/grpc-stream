defmodule StreamServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GrpcReflection,
      {GRPC.Server.Supervisor, endpoint: StreamServer.Endpoint, port: 50051, start_server: true}
    ]

    opts = [strategy: :one_for_one, name: StreamServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
