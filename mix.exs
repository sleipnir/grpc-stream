defmodule GRPCStream.MixProject do
  use Mix.Project

  @app :grpc_stream
  @vsn "0.1.0"
  @description """
  gRPC streaming package for Elixir.
  This package provides a simple way to handle gRPC streaming in Elixir applications.
  It includes a server and client implementation for streaming data over gRPC.
  """
  @package [
    name: :grpc_stream,
    files: ["lib", "mix.exs", "README.md", "LICENSE"],
    maintainers: ["Adriano Sants <sleipnir@eigr.io>"],
    licenses: ["Apache-2.0"],
    links: %{"GitHub" => "https://github.com/sleipnir/grpc-stream"}
  ]

  def project do
    [
      app: @app,
      version: @vsn,
      elixir: "~> 1.18",
      description: @description,
      package: @package,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.10"},
      {:flow, "~> 1.2"}
    ]
  end
end
