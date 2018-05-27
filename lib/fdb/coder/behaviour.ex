defmodule FDB.Coder.Behaviour do
  @callback encode(any, opts :: term) :: binary
  @callback decode(binary, opts :: term) :: {any, binary}
end
