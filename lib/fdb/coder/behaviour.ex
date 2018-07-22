defmodule FDB.Coder.Behaviour do
  @moduledoc """
  Refer modules named FDB.Coder.* for sample implementation.
  """
  @callback encode(any, opts :: any) :: binary
  @callback decode(binary, opts :: any) :: {any, binary}
  @callback range(any, opts :: any) :: {binary, binary}

  defmacro __using__(_opts) do
    quote do
      @behaviour FDB.Coder.Behaviour

      @impl true
      def range(nil, _), do: {<<>>, <<>>}
      def range(value, opts), do: {encode(value, opts), <<>>}

      defoverridable FDB.Coder.Behaviour
    end
  end
end
