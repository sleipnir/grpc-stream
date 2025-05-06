defmodule GrpcStreamTest do
  use ExUnit.Case
  doctest GrpcStream

  test "from/2 creates a flow from enumerable input" do
    input = [%{message: "a"}, %{message: "b"}]

    flow =
      GrpcStream.from(input, max_demand: 1)
      |> GrpcStream.map(& &1)
      |> IO.inspect(label: "Flow output")

    result = Enum.to_list(GrpcStream.to_flow(flow))
    assert result == input
  end
end
