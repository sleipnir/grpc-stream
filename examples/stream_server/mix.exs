defmodule StreamServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :stream_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {StreamServer.Application, []}
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.10"},
      # {:google_protos, "~> 0.4"},
      {:protobuf_generate, "~> 0.1.1", only: :dev},
      {:grpc_reflection, "~> 0.1"},
      {:grpc_stream, path: "../.."}
    ]
  end
end
