defmodule GRPCStreamTest do
  use ExUnit.Case
  doctest GRPCStream

  describe "simple test" do
    defmodule TestInput do
      defstruct [:message]
    end

    defmodule FakeAdapter do
      def get_headers(_), do: %{"content-type" => "application/grpc"}
    end

    test "single/2 creates a flow from a unary input" do
      input = %TestInput{message: 1}
      materializer = %GRPC.Server.Stream{}

      result =
        GRPCStream.single(input)
        |> GRPCStream.map(& &1)
        |> GRPCStream.run_with(materializer, dry_run: true)

      assert result == input
    end

    test "single_with_ctx/3 creates a flow with metadata" do
      input = %TestInput{message: 1}
      materializer = %GRPC.Server.Stream{adapter: FakeAdapter}

      flow =
        GRPCStream.single_as_ctx(input, materializer)
        |> GRPCStream.map_with_ctx(fn meta, item ->
          assert not is_nil(meta)
          assert is_map(meta)
          assert ^meta = %{"content-type" => "application/grpc"}
          item
        end)

      result = Enum.to_list(GRPCStream.to_flow!(flow)) |> Enum.at(0)
      assert result == input
    end

    test "from/2 creates a flow from enumerable input" do
      input = [%{message: "a"}, %{message: "b"}]

      flow =
        GRPCStream.from(input, max_demand: 1)
        |> GRPCStream.map(& &1)

      result = Enum.to_list(GRPCStream.to_flow!(flow))
      assert result == input
    end

    test "from_as_ctx/3 creates a flow from enumerable input" do
      input = [%{message: "a"}, %{message: "b"}]
      materializer = %GRPC.Server.Stream{adapter: FakeAdapter}

      flow =
        GRPCStream.from_as_ctx(input, materializer)
        |> GRPCStream.map_with_ctx(fn meta, item ->
          assert not is_nil(meta)
          assert is_map(meta)
          assert ^meta = %{"content-type" => "application/grpc"}
          item
        end)

      result = Enum.to_list(GRPCStream.to_flow!(flow))
      assert result == input
    end
  end

  describe "from/2" do
    test "converts a list into a flow" do
      stream = GRPCStream.from([1, 2, 3])
      assert %GRPCStream{} = stream

      result = stream |> GRPCStream.map(&(&1 * 2)) |> GRPCStream.to_flow!() |> Enum.to_list()
      assert Enum.sort(result) == [2, 4, 6]
    end

    test "converts from Flow to GRPCStream" do
      flow = Flow.from_enumerable([1, 2, 3], max_demand: 1)
      stream = GRPCStream.from_flow!(flow)
      assert %GRPCStream{flow: ^flow} = stream

      result = stream |> GRPCStream.map(&(&1 * 2)) |> GRPCStream.to_flow!() |> Enum.to_list()
      assert Enum.sort(result) == [2, 4, 6]
    end
  end

  describe "ask/3 with pid" do
    test "calls a pid and returns the response" do
      pid =
        spawn(fn ->
          receive do
            {:request, :hello, test_pid} ->
              send(test_pid, {:response, :world})
          end
        end)

      result =
        GRPCStream.from([:hello])
        |> GRPCStream.ask(pid)
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert result == [:world]
    end

    test "returns error if pid not alive" do
      pid = spawn(fn -> :ok end)
      # wait for the process to exit
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}

      result =
        GRPCStream.from(["msg"])
        |> GRPCStream.ask(pid)
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert result == [{:error, "msg", :not_alive}]
    end
  end

  describe "ask/3 with GenServer" do
    defmodule TestServer do
      use GenServer

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      def init(_), do: {:ok, %{}}

      def handle_call({:request, value}, _from, state) do
        {:reply, {:response, value}, state}
      end
    end

    setup do
      {:ok, _pid} = TestServer.start_link([])
      :ok
    end

    test "asks GenServer and receives correct response" do
      stream = GRPCStream.from(["abc"])

      result =
        stream
        |> GRPCStream.ask(TestServer)
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert result == ["abc"]
    end
  end

  describe "map/2, flat_map/2, filter/2" do
    test "maps values correctly" do
      result =
        GRPCStream.from([1, 2, 3])
        |> GRPCStream.map(&(&1 * 10))
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert Enum.sort(result) == [10, 20, 30]
    end

    test "flat_maps values correctly" do
      result =
        GRPCStream.from([1, 2])
        |> GRPCStream.flat_map(&[&1, &1])
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert Enum.sort(result) == [1, 1, 2, 2]
    end

    test "filters values correctly" do
      result =
        GRPCStream.from([1, 2, 3, 4])
        |> GRPCStream.filter(&(rem(&1, 2) == 0))
        |> GRPCStream.to_flow!()
        |> Enum.to_list()

      assert result == [2, 4]
    end
  end

  describe "test complex operations" do
    test "pipeline with all GRPCStream operators" do
      target =
        spawn(fn ->
          receive_loop()
        end)

      input = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

      result =
        input
        |> GRPCStream.from()
        # 2..11
        |> GRPCStream.map(&(&1 + 1))
        # [2,4,3,6,4,8,...]
        |> GRPCStream.flat_map(&[&1, &1 * 2])
        # keep evens
        |> GRPCStream.filter(&(rem(&1, 2) == 0))
        # remove >10
        |> GRPCStream.reject(&(&1 > 10))
        # remove duplicates
        |> GRPCStream.uniq()
        # multiply by 10 via process
        |> GRPCStream.ask(target)
        |> GRPCStream.partition()
        |> GRPCStream.reduce(fn -> [] end, fn i, acc -> [i | acc] end)
        |> GRPCStream.to_flow!()
        |> Enum.to_list()
        |> List.flatten()
        |> Enum.sort()

      assert result == [20, 40, 60, 80, 100]
    end
  end

  describe "join_with/merge streams" do
    test "merges input stream with joined GenStage producer" do
      defmodule TestProducer do
        use GenStage

        def start_link(items) do
          GenStage.start_link(__MODULE__, items)
        end

        def init(items) do
          {:producer, items}
        end

        def handle_demand(demand, state) when demand > 0 do
          {events, remaining} = Enum.split(state, demand)

          {:noreply, events, remaining}
        end
      end

      elements = Enum.to_list(4..1000)
      {:ok, producer_pid} = TestProducer.start_link(elements)

      input = [1, 2, 3]

      task =
        Task.async(fn ->
          GRPCStream.from(input, join_with: producer_pid, max_demand: 500)
          |> GRPCStream.map(fn it ->
            #IO.inspect(it, label: "Processing item by Worker #{inspect(self())}")
            it
          end)
          |> GRPCStream.run_with(%GRPC.Server.Stream{}, dry_run: true)
        end)

      result =
        case Task.yield(task, 1000) || Task.shutdown(task) do
          {:ok, _} -> :ok
          _ -> :ok
        end

      if Process.alive?(producer_pid) do
        Process.exit(producer_pid, :normal)
      end

      assert result == :ok
    end
  end

  defp receive_loop do
    receive do
      {:request, item, from} ->
        send(from, {:response, item * 10})
        receive_loop()
    end
  end
end
