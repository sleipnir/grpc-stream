defmodule GRPCStream.Producer do
  @moduledoc false
  use GenStage

  def start_link(input_stream, opts) do
    opts = Keyword.drop(opts, [:unbounded_sink_pid])
    IO.inspect(opts, label: "Producer options")
    GenStage.start_link(__MODULE__, input_stream, opts)
  end

  def init(input_stream) do
    IO.inspect(input_stream, label: "Producer input stream")
    {:producer, %{enum: input_stream, buffer: []}}
  end

  def handle_demand(demand, %{enum: enum, buffer: _buffer} = state) when demand > 0 do
    IO.inspect(demand, label: "Producer demand")
    {events, new_enum} = take_n(enum, demand)
    {:noreply, events, %{state | enum: new_enum}}
  end

  defp take_n(enum, 0), do: {[], enum}

  defp take_n(enum, n) do
    IO.inspect(n, label: "take_n")
    stream = Stream.chunk_every(enum, n, n, :discard)
    IO.inspect(stream, label: "Stream chunked")

    case Enum.fetch(stream, 0) do
      {:ok, chunk} ->
        r = {chunk, Stream.drop(enum, n)}
        IO.inspect(r, label: "take_n result")
        r

      :error ->
        {[], enum}
    end
  end
end
