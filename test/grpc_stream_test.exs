defmodule GrpcStreamTest do
  use ExUnit.Case
  doctest GrpcStream

  test "greets the world" do
    assert GrpcStream.hello() == :world
  end
end
