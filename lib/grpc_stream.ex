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

  defstruct flow: nil

  @type t :: %__MODULE__{flow: Flow.t()}

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

    case unbounded_producer do
      unbounded_pid when is_pid(unbounded_pid) ->
        {:ok, pid} = GRPCStream.Producer.start_link(req_enum, opts)

        flow = Flow.from_stages([pid, unbounded_pid], opts)
        %__MODULE__{flow: flow}

      _ ->
        flow = Flow.from_enumerable(req_enum, opts)
        %__MODULE__{flow: flow}
    end
  end

  @doc """
  Converts a `Flow` into a `GrpcStream`.
  """
  @spec from_flow(Flow.t(), Keyword.t()) :: t()
  def from_flow(%Flow{} = flow, opts \\ []), do: from(flow, opts)

  @doc """
  Converts a `GrpcStream` into a `Flow`.
  """
  def to_flow(%__MODULE__{flow: flow}), do: flow

  @doc """
  Sends the results of a `Flow` as gRPC responses using the provided stream.

  ## Parameters

    - `flow`: A `Flow` containing messages to send as gRPC replies.
    - `stream`: The gRPC server stream (of type `GRPC.Server.Stream`) to send responses to.
    - `opts`: (optional) Keyword options, currently unused.

  ## Example

      GrpcStream.materialize(flow, stream)

  """
  def materialize(%__MODULE__{flow: flow} = _stream, %Stream{} = from, opts \\ []) do
    is_dry_run? = Keyword.get(opts, :dry_run, false)

    flow
    |> Flow.map(fn msg ->
      if is_dry_run?, do: :nothing, else: send_response(from, msg)

      flow
    end)
    |> Flow.run()
  end

  defp send_response(from, msg) do
    GRPC.Server.send_reply(from, msg)
  end

  @doc """
  Applies the given function filtering each input in parallel.
  """
  @spec filter(t(), (term -> term)) :: t
  def filter(%__MODULE__{flow: flow}, filter) do
    %__MODULE__{flow: Flow.filter(flow, filter)}
  end

  @spec map(t(), (term -> term)) :: t
  def map(%__MODULE__{flow: flow}, mapper) do
    %__MODULE__{flow: Flow.map(flow, mapper)}
  end

  @doc """
  Applies the given function mapping each input in parallel and
  flattening the result, but only one level deep.
  """
  @spec flat_map(t, (term -> Enumerable.t())) :: t
  def flat_map(%__MODULE__{flow: flow}, flat_mapper) do
    %__MODULE__{flow: Flow.flat_map(flow, flat_mapper)}
  end

  @doc """
  Applies the given function rejecting each input in parallel.
  """
  @spec reject(t, (term -> term)) :: t
  def reject(%__MODULE__{flow: flow}, filter) do
    %__MODULE__{flow: Flow.reject(flow, filter)}
  end

  @doc """
  Reduces the given values with the given accumulator.

  `acc_fun` is a function that receives no arguments and returns
  the actual accumulator.
  """
  @spec reduce(t, (-> acc), (term, acc -> acc)) :: t when acc: term()
  def reduce(%__MODULE__{flow: flow}, acc_fun, reducer_fun) do
    %__MODULE__{flow: Flow.reduce(flow, acc_fun, reducer_fun)}
  end
end
