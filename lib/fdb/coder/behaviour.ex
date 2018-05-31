defmodule FDB.Coder.Behaviour do
  @callback encode(any, opts :: term) :: binary
  @callback decode(binary, opts :: term) :: {any, binary}
  @callback range(any, opts :: term) :: {binary, binary}

  @optional_callbacks range: 2
end
