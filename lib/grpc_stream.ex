defmodule GrpcStream do
  @moduledoc """
  Adapter module for working with gRPC server-side streaming in Elixir using
  `Flow` with support for backpressure via GenStage.

  ## Features

    - Converts a gRPC request stream (`req_enum`) into a `Flow` with backpressure support.
    - Materializes the `Flow` into outgoing gRPC responses.
    - Supports optional unbounded producers to be attached for high-throughput streaming pipelines.

  ## Example: Basic request-response stream

      defmodule MyGRPCService do
        use GRPC.Server, service: MyService.Service
        alias GrpcStream

        def route_chat(req_enum, stream) do
          GrpcStream.from(req_enum, max_demand: 10)
          |> Flow.map(fn note ->
            # Process the incoming note
            # and prepare a response
          end)
          |> GrpcStream.materialize(stream)

          stream
        end
      end

  ## Example: Using an unbounded producer

  You can pass an already-started `GenStage` producer to `:unbounded_sink_pid`.
  This is useful if you want to consume from an infinite or external event source
  in addition to the gRPC stream.

      defmodule MyGRPCService do
        use GRPC.Server, service: MyService.Service
        alias GrpcStream

        def stream_events(req_enum, stream) do
          # Assuming you have a RabbitMQ or another unbounded source of data producer that is a GenStage producer
          {:ok, rabbitmq_producer} = MyApp.RabbitMQ.Producer.start_link([])

          GrpcStream.from(req_enum, unbounded_sink_pid: rabbit_producer, max_demand: 10)
          |> Flow.map(&transform_event/1)
          |> GrpcStream.materialize(stream)
        end

        defp transform_event({_, grpc_msg}), do: grpc_msg
        defp transform_event(event), do: %MyGRPC.Event{data: inspect(event)}
      end

  """
  alias GRPC.Server.Stream

  @doc """
  Converts a gRPC request enumerable into a `Flow` pipeline with support for backpressure.

  ## Parameters

    - `req_enum`: The enumerable stream of incoming gRPC messages (from `elixir-grpc`).
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Options

    - `:unbounded_sink_pid` - (optional) An additional producer stage PID to include in the Flow.

  ## Returns

    - A `Flow` that emits elements from the gRPC stream under demand.

  ## Example

      flow = GrpcStream.from(req_enum, max_demand: 5)

  """
  @spec from(Enumerable.t(), Keyword.t()) :: Flow.t()
  def from(req_enum, opts \\ []) do
    unbounded_producer = Keyword.get(opts, :unbounded_sink_pid)

    {:ok, pid} = GRPCStream.Producer.start_link(req_enum, opts)

    producers =
      case unbounded_producer do
        other_pid when is_pid(other_pid) ->
          [pid, other_pid]

        _ ->
          [pid]
      end

    Flow.from_stages(producers, opts)
  end

  @doc """
  Sends the results of a `Flow` as gRPC responses using the provided stream.

  ## Parameters

    - `flow`: A `Flow` containing messages to send as gRPC replies.
    - `stream`: The gRPC server stream (of type `GRPC.Server.Stream`) to send responses to.
    - `opts`: (optional) Keyword options, currently unused.

  ## Example

      GrpcStream.materialize(flow, stream)

  """
  def materialize(%Flow{} = flow, %Stream{} = from, _opts \\ []) do
    flow
    |> Flow.map(fn msg ->
      send_response(from, msg)
      flow
    end)
    |> Flow.run()
  end

  defp send_response(from, msg) do
    GRPC.Server.send_reply(from, msg)
  end
end
