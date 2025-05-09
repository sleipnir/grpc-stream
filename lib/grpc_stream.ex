defmodule GRPCStream do
  @moduledoc """
  Adapter module for working with gRPC server-side streaming in Elixir using
  `Flow` with support for backpressure via GenStage.

  ## Features

    - Converts a gRPC request stream (`input`) into a `Flow` with backpressure support.
    - Materializes the `Flow` into outgoing gRPC responses.
    - Supports optional unbounded producers to be attached for high-throughput streaming pipelines.

  ## Example: Basic request-response stream

      defmodule MyGRPCService do
        use GRPC.Server, service: MyService.Service
        alias GRPCStream

        def route_chat(input, stream) do
          GRPCStream.from(input, max_demand: 10)
          |> Flow.map(fn note ->
            # Process the incoming note
            # and prepare a response
          end)
          |> GRPCStream.run_with(stream)
        end
      end

  ## Example: Using an unbounded producer

  You can pass an already-started `GenStage` producer to `:join_with`.
  This is useful if you want to consume from an infinite or external event source
  in addition to the gRPC stream.

      defmodule MyGRPCService do
        use GRPC.Server, service: MyService.Service
        alias GRPCStream

        def stream_events(input, stream) do
          # Assuming you have a RabbitMQ or another unbounded source of data producer that is a GenStage producer
          {:ok, rabbitmq_producer} = MyApp.RabbitMQ.Producer.start_link([])

          GRPCStream.from(input, join_with: rabbit_producer, max_demand: 10)
          |> Flow.map(&transform_event/1)
          |> GRPCStream.run_with(stream)
        end

        defp transform_event({_, grpc_msg}), do: grpc_msg
        defp transform_event(event), do: %MyGRPC.Event{data: inspect(event)}
      end

  """
  alias GRPCStream.Operators
  alias GRPC.Server.Stream

  defstruct flow: nil, options: [], metadata: %{}

  @type t :: %__MODULE__{flow: Flow.t(), options: Keyword.t(), metadata: map()}

  @type item :: any()

  @type reason :: any()

  @doc """
  Converts a gRPC request enumerable into a `Flow` pipeline with support for backpressure.

  ## Parameters

    - `input`: The enumerable stream of incoming gRPC messages (from `elixir-grpc`).
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Options

    - `:join_with` - (optional) An additional producer stage PID to include in the Flow.
    - `:dispatcher` - (optional) The dispatcher to use for the Flow. Default is `GenStage.DemandDispatcher`.

  ## Returns

    - A `GRPCStream` that emits elements from the gRPC stream under demand.

  ## Example

      flow = GRPCStream.from(request, max_demand: 5)

  """
  @spec from(any(), Keyword.t()) :: t()
  def from(input, opts \\ [])

  def from(%Elixir.Stream{} = input, opts), do: build_grpc_stream(input, opts)

  def from(input, opts) when is_list(input), do: build_grpc_stream(input, opts)

  def from(input, opts) when not is_nil(input), do: from([input], opts)

  @doc """
  Converts a gRPC request enumerable into a `Flow` pipeline while extracting and propagating context metadata from the `GRPC.Server.Stream`.

  This is useful for unary gRPC calls that require metadata propagation within a Flow-based pipeline.

  ## Parameters

    - `input`: The enumerable stream of incoming gRPC messages.
    - `materializer`: A `%GRPC.Server.Stream{}` struct representing the current gRPC stream context.
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Behavior

    - Automatically extracts gRPC metadata from the stream headers and injects it into the options as `:metadata`.
    - Sets `:unary` to `true` in the options to indicate unary processing.

  ## Returns

    - A `GRPCStream` that emits elements from the gRPC stream under demand.

  ## Example

      flow = GRPCStream.from_as_ctx(request, stream, max_demand: 10)

  """
  @spec from_as_ctx(any(), GRPC.Server.Stream.t(), Keyword.t()) :: t()
  def from_as_ctx(input, %GRPC.Server.Stream{} = materializer, opts \\ []) do
    meta = GRPC.Stream.get_headers(materializer) || %{}
    opts = Keyword.merge(opts, unary: true, metadata: meta)
    from(input, opts)
  end
  
  @doc """
  Converts a single gRPC request into a `Flow` pipeline with support for backpressure.
  This is useful for unary gRPC requests where you want to use the Flow API.

  ## Parameters

    - `input`: The single gRPC message to convert into a Flow.
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Options
    - `:join_with` - (optional) An additional producer stage PID to include in the Flow.
    - `:dispatcher` - (optional) The dispatcher to use for the Flow. Default is `GenStage.DemandDispatcher`.

  ## Returns
    - A `GRPCStream` that emits the single gRPC message under demand.

  ## Example

      flow = GRPCStream.single(request, max_demand: 5)
  """
  @spec single(any(), Keyword.t()) :: t()
  def single(input, opts \\ []) when is_struct(input),
    do: build_grpc_stream([input], Keyword.merge(opts, unary: true))

  @doc """
  Converts a single gRPC request into a `Flow` pipeline while extracting and propagating context metadata from the `GRPC.Server.Stream`.

  This is useful for unary gRPC calls that require metadata propagation within a Flow-based pipeline.

  ## Parameters

    - `input`: The enumerable stream of incoming gRPC messages.
    - `materializer`: A `%GRPC.Server.Stream{}` struct representing the current gRPC stream context.
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Behavior

    - Automatically extracts gRPC metadata from the stream headers and injects it into the options as `:metadata`.

  ## Returns

    - A `GRPCStream` that emits the single gRPC message under demand.

  ## Example

      flow = GRPCStream.single_as_ctx(request, stream, max_demand: 10)

  """
  @spec single_as_ctx(any(), GRPC.Server.Stream.t(), Keyword.t()) :: t()
  def single_as_ctx(input, %GRPC.Server.Stream{} = materializer, opts \\ []) when is_struct(input) do
    meta = GRPC.Stream.get_headers(materializer) || %{}
    opts = Keyword.merge(opts, unary: true, metadata: meta)
    single(input, opts)
  end

  defp build_grpc_stream(input, opts) do
    dispatcher = Keyword.get(opts, :default_dispatcher, GenStage.DemandDispatcher)

    flow =
      case Keyword.get(opts, :join_with) do
        pid when is_pid(pid) ->
          opts = Keyword.drop(opts, [:join_with, :default_dispatcher, :metadata])

          input_flow = Flow.from_enumerable(input, opts)
          other_flow = Flow.from_stages([pid], opts)
          Flow.merge([input_flow, other_flow], dispatcher, opts)

        # handle Elixir.Stream joining
        other when is_list(other) or is_function(other) ->
          Flow.from_enumerables([input, other], opts)

        _ ->
          opts = Keyword.drop(opts, [:join_with, :default_dispatcher, :metadata])
          Flow.from_enumerable(input, opts)
      end

    %__MODULE__{flow: flow, options: opts, metadata: Keyword.get(opts, :metadata, %{})}
  end

  @doc """
  Converts a `Flow` into a `GRPCStream`.
  """
  @spec from_flow!(Flow.t(), Keyword.t()) :: t()
  def from_flow!(%Flow{} = flow, opts \\ []) do
    if Keyword.has_key?(opts, :join_with) do
      raise ArgumentError, "join_with option is not supported for Flow input"
    end

    %__MODULE__{flow: flow, options: opts}
  end

  @doc """
  Converts a `GRPCStream` into a `Flow`.
  """
  @spec to_flow!(t()) :: Flow.t()
  def to_flow!(%__MODULE__{flow: nil}) do
    raise ArgumentError, "GRPCStream has no flow, initialize it with from/2"
  end

  def to_flow!(%__MODULE__{flow: flow}), do: flow

  @doc """
  Sends the results of a `Flow` as gRPC responses using the provided stream.

  ## Parameters

    - `flow`: A `Flow` containing messages to send as gRPC replies.
    - `stream`: The gRPC server stream (of type `GRPC.Server.Stream`) to send responses to.
    - `opts`: (optional) Keyword options, currently unused.

  ## Example

      GRPCStream.run_with(flow, stream)

  """
  @spec run_with(t(), Stream.t(), Keyword.t()) :: :ok | any()
  def run_with(
        %__MODULE__{flow: flow, options: flow_opts} = _stream,
        %Stream{} = from,
        opts \\ []
      ) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    unary? = Keyword.get(flow_opts, :unary, false)

    if unary? do
      flow
      |> Enum.to_list()
      |> List.flatten()
      |> List.first()
    else
      flow
      |> Flow.map(fn msg ->
        unless dry_run?, do: send_response(from, msg)
        flow
      end)
      |> Flow.run()
    end
  end

  defp send_response(from, msg) do
    GRPC.Server.send_reply(from, msg)
  end

  @doc """
  Sends a stream item to the given target process and waits for a response.
  The target process must be a PID. The payload following in the tuple {:request, item, from}
  is sent to the target process, where `item` is the item from the GRPCStream and `from` is the
  PID of the current process. 
  In other words, the contract is to send {:request, item, from_pid} and wait for a response in the format {:response, msg}

  This function also accepts a GenServer module as target. In this case the payload following in the tuple {:request, item}
  is sent to the target GenServer, where `item` is the item from the GRPCStream.
  In other words, for GenServer's the contract is to send {:request, item} and wait for a response in the format {:response, msg}
  """
  @spec ask(t(), pid | atom, non_neg_integer) :: t() | {:error, item(), reason()}
  defdelegate ask(stream, target, timeout \\ 5000), to: Operators

  @doc """
  Same as ask/3 but with side-effects

  Side Effect:

  Exceptions thrown by this function will cause the Flow worker to crash, causing an EXIT that ends the pipeline and fails the test.

  Caution: Prefer to use ask/3 and deal with the different types instead of throwing exceptions.
  """
  @spec ask!(t(), pid | atom, non_neg_integer) :: t()
  defdelegate ask!(stream, target, timeout \\ 5000), to: Operators

  @doc """
  Applies the given function filtering each input in parallel.
  """
  @spec filter(t(), (term -> term)) :: t
  defdelegate filter(stream, filter), to: Operators

  @doc """
  Applies the given function mapping each input in parallel and
  flattening the result, but only one level deep.
  """
  @spec flat_map(t, (term -> Enumerable.t())) :: t()
  defdelegate flat_map(stream, flat_mapper), to: Operators

  @doc """
  Applies the given function mapping each input.
  """
  @spec map(t(), (term -> term)) :: t()
  defdelegate map(stream, mapper), to: Operators

  defdelegate map_with_ctx(stream, mapper), to: Operators

  @doc """
  Creates a new partition for the given GRPCStream with the given options.

  Every time this function is called, a new partition is created.
  It is typically recommended to invoke it before a reducing function,
  such as `reduce/3`, so data belonging to the same partition can be
  kept together.

  However, notice that unnecessary partitioning will increase memory
  usage and reduce throughput with no benefit whatsoever. GRPCStream takes
  care of using all cores regardless of the number of times you call
  partition. You should only partition when the problem you are trying
  to solve requires you to route the data around. Such as the problem
  presented in `Flow`'s module documentation. If you can solve a problem
  without using partition at all, that is typically preferred. Those
  are typically called "embarrassingly parallel" problems.
  """
  @spec partition(t(), keyword()) :: t()
  defdelegate partition(stream, options \\ []), to: Operators

  @doc """
  Reduces the given values with the given accumulator.

  `acc_fun` is a function that receives no arguments and returns
  the actual accumulator.
  """
  @spec reduce(t, (-> acc), (term, acc -> acc)) :: t when acc: term()
  defdelegate reduce(stream, acc_fun, reducer_fun), to: Operators

  @doc """
  Applies the given function rejecting each input in parallel.
  """
  @spec reject(t, (term -> term)) :: t
  defdelegate reject(stream, filter), to: Operators

  @doc """
  Only emit unique events.
  """
  @spec uniq(t) :: t
  defdelegate uniq(stream), to: Operators

  @doc """
  Only emit events that are unique according to the `by` function.
  """
  @spec uniq_by(t, (term -> term)) :: t
  defdelegate uniq_by(stream, fun), to: Operators
end
