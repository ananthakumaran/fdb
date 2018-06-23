defmodule FDB.Coder.Behaviour do
  @callback encode(any, opts :: term) :: binary
  @callback decode(binary, opts :: term) :: {any, binary}
  @callback range(any, opts :: term) :: {binary, atom}

  defmacro __using__(_opts) do
    quote do
      @behaviour FDB.Coder.Behaviour

      def range(nil, _), do: {<<>>, :partial}
      def range(value, opts), do: {encode(value, opts), :complete}

      defoverridable FDB.Coder.Behaviour
    end
  end
end
