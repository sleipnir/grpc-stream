defmodule GRPCStream.Producer do
  @moduledoc false
  use GenStage

  def start_link(input_stream, opts) do
    opts = Keyword.drop(opts, [:unbounded_sink_pid])
    GenStage.start_link(__MODULE__, input_stream, opts)
  end

  def init(input_stream) do
    {:producer, %{enum: input_stream, buffer: []}}
  end

  def handle_demand(demand, %{enum: enum, buffer: _buffer} = state) when demand > 0 do
    {events, new_enum} = take_n(enum, demand)
    {:noreply, events, %{state | enum: new_enum}}
  end

  defp take_n(enum, 0), do: {[], enum}

  defp take_n(enum, n) do
    stream = Stream.chunk_every(enum, n, n, :discard)

    case Enum.fetch(stream, 0) do
      {:ok, chunk} ->
        {chunk, Stream.drop(enum, n)}

      :error ->
        {[], enum}
    end
  end
end
