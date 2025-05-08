defmodule GrpcStream do
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
        alias GrpcStream

        def route_chat(input, stream) do
          GrpcStream.from(input, max_demand: 10)
          |> Flow.map(fn note ->
            # Process the incoming note
            # and prepare a response
          end)
          |> GrpcStream.materialize(stream)
        end
      end

  ## Example: Using an unbounded producer

  You can pass an already-started `GenStage` producer to `:join_with`.
  This is useful if you want to consume from an infinite or external event source
  in addition to the gRPC stream.

      defmodule MyGRPCService do
        use GRPC.Server, service: MyService.Service
        alias GrpcStream

        def stream_events(input, stream) do
          # Assuming you have a RabbitMQ or another unbounded source of data producer that is a GenStage producer
          {:ok, rabbitmq_producer} = MyApp.RabbitMQ.Producer.start_link([])

          GrpcStream.from(input, join_with: rabbit_producer, max_demand: 10)
          |> Flow.map(&transform_event/1)
          |> GrpcStream.materialize(stream)
        end

        defp transform_event({_, grpc_msg}), do: grpc_msg
        defp transform_event(event), do: %MyGRPC.Event{data: inspect(event)}
      end

  """
  alias GRPC.Server.Stream

  defstruct flow: nil, options: []

  @type t :: %__MODULE__{flow: Flow.t(), options: Keyword.t()}

  @type item :: any()

  @type reason :: any()

  @doc """
  Converts a gRPC request enumerable into a `Flow` pipeline with support for backpressure.

  ## Parameters

    - `input`: The enumerable stream of incoming gRPC messages (from `elixir-grpc`).
    - `opts`: Optional keyword list for configuring the Flow or GenStage producer.

  ## Options

    - `:join_with` - (optional) An additional producer stage PID to include in the Flow.
    - `:unary` - Required if you want to use pipelines for unary grpc requests. Default `false`.

  ## Returns

    - A `Flow` that emits elements from the gRPC stream under demand.

  ## Example

      flow = GrpcStream.from(request, max_demand: 5)

  """
  @spec from(Enumerable.t(), Keyword.t()) :: Flow.t()
  def from(input, opts \\ [])

  def from(%Elixir.Stream{} = input, opts), do: build_grpc_stream(input, opts)

  def from(input, opts) when is_list(input), do: build_grpc_stream(input, opts)

  def from(input, opts) when not is_nil(input), do: from([input], opts)

  defp build_grpc_stream(input, opts) do
    flow =
      case Keyword.get(opts, :join_with) do
        pid when is_pid(pid) ->
          {:ok, input_pid} = GRPCStream.Producer.start_link(input, opts)
          Flow.from_stages([input_pid, pid], opts)

        # handle Elixir.Stream joining
        other when is_list(other) or is_function(other) ->
          Flow.from_enumerables([input, other], opts)

        _ ->
          Flow.from_enumerable(input, opts)
      end

    %__MODULE__{flow: flow, options: opts}
  end

  @doc """
  Converts a `Flow` into a `GrpcStream`.
  """
  @spec from_flow!(Flow.t(), Keyword.t()) :: t()
  def from_flow!(%Flow{} = flow, opts \\ []) do
    if Keyword.has_key?(opts, :join_with) do
      raise ArgumentError, "join_with option is not supported for Flow input"
    end

    %__MODULE__{flow: flow, options: opts}
  end

  @doc """
  Converts a `GrpcStream` into a `Flow`.
  """
  @spec to_flow!(t()) :: Flow.t()
  def to_flow!(%__MODULE__{flow: nil}) do
    raise ArgumentError, "GrpcStream has no flow, initialize it with from/2"
  end

  def to_flow!(%__MODULE__{flow: flow}), do: flow

  @doc """
  Sends the results of a `Flow` as gRPC responses using the provided stream.

  ## Parameters

    - `flow`: A `Flow` containing messages to send as gRPC replies.
    - `stream`: The gRPC server stream (of type `GRPC.Server.Stream`) to send responses to.
    - `opts`: (optional) Keyword options, currently unused.

  ## Example

      GrpcStream.materialize(flow, stream)

  """
  @spec materialize(t(), Stream.t(), Keyword.t()) :: :ok | any()
  def materialize(
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
  is sent to the target process, where `item` is the item from the GrpcStream and `from` is the
  PID of the current process. 
  In other words, the contract is to send {:request, item, from_pid} and wait for a response in the format {:response, msg}

  This function also accepts a GenServer module as target. In this case the payload following in the tuple {:request, item}
  is sent to the target GenServer, where `item` is the item from the GrpcStream.
  In other words, for GenServer's the contract is to send {:request, item} and wait for a response in the format {:response, msg}
  """
  @spec ask(t(), pid | atom, non_neg_integer) :: t() | {:error, item(), reason()}
  def ask(stream, target, timeout \\ 5000)

  def ask(%__MODULE__{flow: flow} = stream, target, timeout) when is_pid(target) do
    mapper = fn item ->
      if Process.alive?(target) do
        send(target, {:request, item, self()})

        result =
          receive do
            {:response, res} -> res
          after
            timeout -> {:error, item, :timeout}
          end

        result
      else
        {:error, item, :not_alive}
      end
    end

    %__MODULE__{stream | flow: Flow.map(flow, mapper)}
  end

  def ask(%__MODULE__{flow: flow} = stream, target, timeout) when is_atom(target) do
    mapper = fn item ->
      if function_exported?(target, :handle_call, 3) do
        try do
          case GenServer.call(target, {:request, item}, timeout) do
            {:response, res} ->
              res

            other ->
              {:error, item,
               "Expected response from #{inspect(target)} to be in the format {:response, msg}. Found #{inspect(other)}"}
          end
        rescue
          reason ->
            {:error, item, reason}
        end
      else
        {:error, item, "#{inspect(target)} must implement the GenServer behavior"}
      end
    end

    %__MODULE__{stream | flow: Flow.map(flow, mapper)}
  end

  @doc """
  Same as ask/3 but with side-effects

  Side Effect:

  Exceptions thrown by this function will cause the Flow worker to crash, causing an EXIT that ends the pipeline and fails the test.

  Caution: Prefer to use ask/3 and deal with the different types instead of throwing exceptions.
  """
  @spec ask!(t(), pid | atom, non_neg_integer) :: t()
  def ask!(stream, target, timeout \\ 5000)

  def ask!(%__MODULE__{flow: flow} = stream, target, timeout) when is_pid(target) do
    mapper = fn item ->
      if Process.alive?(target) do
        send(target, {:request, item, self()})

        result =
          receive do
            {:response, res} -> res
          after
            timeout ->
              raise "Timeout waiting for response from #{inspect(target)}"
          end

        result
      else
        raise "Target #{inspect(target)} is not alive. Cannot send request to it."
      end
    end

    %__MODULE__{stream | flow: Flow.map(flow, mapper)}
  end

  def ask!(%__MODULE__{flow: flow} = stream, target, timeout) when is_atom(target) do
    if not function_exported?(target, :handle_call, 3) do
      raise ArgumentError, "#{inspect(target)} must implement the GenServer behavior"
    end

    mapper = fn item ->
      case GenServer.call(target, {:request, item}, timeout) do
        {:response, res} ->
          res

        _ ->
          raise ArgumentError,
                "Expected response from #{inspect(target)} to be in the format {:response, msg}"
      end
    end

    %__MODULE__{stream | flow: Flow.map(flow, mapper)}
  end

  @doc """
  Applies the given function filtering each input in parallel.
  """
  @spec filter(t(), (term -> term)) :: t
  def filter(%__MODULE__{flow: flow} = stream, filter) do
    %__MODULE__{stream | flow: Flow.filter(flow, filter)}
  end

  @doc """
  Applies the given function mapping each input in parallel and
  flattening the result, but only one level deep.
  """
  @spec flat_map(t, (term -> Enumerable.t())) :: t()
  def flat_map(%__MODULE__{flow: flow} = stream, flat_mapper) do
    %__MODULE__{stream | flow: Flow.flat_map(flow, flat_mapper)}
  end

  @doc """
  Applies the given function mapping each input.
  """
  @spec map(t(), (term -> term)) :: t()
  def map(%__MODULE__{flow: flow} = stream, mapper) do
    %__MODULE__{stream | flow: Flow.map(flow, mapper)}
  end

  @doc """
  Creates a new partition for the given GrpcStream with the given options.

  Every time this function is called, a new partition is created.
  It is typically recommended to invoke it before a reducing function,
  such as `reduce/3`, so data belonging to the same partition can be
  kept together.

  However, notice that unnecessary partitioning will increase memory
  usage and reduce throughput with no benefit whatsoever. GrpcStream takes
  care of using all cores regardless of the number of times you call
  partition. You should only partition when the problem you are trying
  to solve requires you to route the data around. Such as the problem
  presented in `Flow`'s module documentation. If you can solve a problem
  without using partition at all, that is typically preferred. Those
  are typically called "embarrassingly parallel" problems.
  """
  @spec partition(t(), keyword()) :: t()
  def partition(%__MODULE__{flow: flow} = stream, options \\ []) do
    %__MODULE__{stream | flow: Flow.partition(flow, options)}
  end

  @doc """
  Reduces the given values with the given accumulator.

  `acc_fun` is a function that receives no arguments and returns
  the actual accumulator.
  """
  @spec reduce(t, (-> acc), (term, acc -> acc)) :: t when acc: term()
  def reduce(%__MODULE__{flow: flow} = stream, acc_fun, reducer_fun) do
    %__MODULE__{stream | flow: Flow.reduce(flow, acc_fun, reducer_fun)}
  end

  @doc """
  Applies the given function rejecting each input in parallel.
  """
  @spec reject(t, (term -> term)) :: t
  def reject(%__MODULE__{flow: flow} = stream, filter) do
    %__MODULE__{stream | flow: Flow.reject(flow, filter)}
  end

  @doc """
  Only emit unique events.
  """
  @spec uniq(t) :: t
  def uniq(%__MODULE__{flow: flow} = stream) do
    %__MODULE__{stream | flow: Flow.uniq(flow)}
  end

  @doc """
  Only emit events that are unique according to the `by` function.
  """
  @spec uniq_by(t, (term -> term)) :: t
  def uniq_by(%__MODULE__{flow: flow} = stream, fun) do
    %__MODULE__{stream | flow: Flow.uniq_by(flow, fun)}
  end
end
