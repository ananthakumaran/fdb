defmodule FDB.Coder.Behaviour do
  @callback encode(any, opts :: any) :: binary
  @callback decode(binary, opts :: any) :: {any, binary}
  @callback range(any, opts :: any) :: {binary, :complete | :partial}

  defmacro __using__(_opts) do
    quote do
      @behaviour FDB.Coder.Behaviour

      @impl true
      def range(nil, _), do: {<<>>, :partial}
      def range(value, opts), do: {encode(value, opts), :complete}

      defoverridable FDB.Coder.Behaviour
    end
  end
end
