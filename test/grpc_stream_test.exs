defmodule GrpcStreamTest do
  use ExUnit.Case
  doctest GrpcStream

  describe "simple test" do
    test "from/2 creates a flow from a unary input" do
      input = 1

      result =
        GrpcStream.from(input, max_demand: 1)
        |> GrpcStream.map(& &1)
        |> GrpcStream.materialize(%GRPC.Server.Stream{}, dry_run: true)

      assert result == :ok
    end

    test "from/2 creates a flow from enumerable input" do
      input = [%{message: "a"}, %{message: "b"}]

      flow =
        GrpcStream.from(input)
        |> GrpcStream.map(& &1)

      result = Enum.to_list(GrpcStream.to_flow(flow))
      assert result == input
    end
  end

  describe "from/2" do
    test "converts a list into a flow" do
      stream = GrpcStream.from([1, 2, 3])
      assert %GrpcStream{} = stream

      result = stream |> GrpcStream.map(&(&1 * 2)) |> GrpcStream.to_flow() |> Enum.to_list()
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
        GrpcStream.from([:hello])
        |> GrpcStream.ask(pid)
        |> GrpcStream.to_flow()
        |> Enum.to_list()

      assert result == [:world]
    end

    test "returns error if pid not alive" do
      pid = spawn(fn -> :ok end)
      # wait for the process to exit
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}

      result =
        GrpcStream.from(["msg"])
        |> GrpcStream.ask(pid)
        |> GrpcStream.to_flow()
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
      stream = GrpcStream.from(["abc"])

      result =
        stream
        |> GrpcStream.ask(TestServer)
        |> GrpcStream.to_flow()
        |> Enum.to_list()

      assert result == ["abc"]
    end
  end

  describe "map/2, flat_map/2, filter/2" do
    test "maps values correctly" do
      result =
        GrpcStream.from([1, 2, 3])
        |> GrpcStream.map(&(&1 * 10))
        |> GrpcStream.to_flow()
        |> Enum.to_list()

      assert Enum.sort(result) == [10, 20, 30]
    end

    test "flat_maps values correctly" do
      result =
        GrpcStream.from([1, 2])
        |> GrpcStream.flat_map(&[&1, &1])
        |> GrpcStream.to_flow()
        |> Enum.to_list()

      assert Enum.sort(result) == [1, 1, 2, 2]
    end

    test "filters values correctly" do
      result =
        GrpcStream.from([1, 2, 3, 4])
        |> GrpcStream.filter(&(rem(&1, 2) == 0))
        |> GrpcStream.to_flow()
        |> Enum.to_list()

      assert result == [2, 4]
    end
  end
end
