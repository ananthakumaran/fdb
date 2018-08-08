defmodule FDB.Coder.DirectoryVersion do
  @moduledoc false
  use FDB.Coder.Behaviour

  @spec new() :: FDB.Coder.t()
  def new() do
    %FDB.Coder{module: __MODULE__, opts: nil}
  end

  @impl true
  def encode({major, minor, patch}, _) do
    <<major::little-integer-unsigned-size(32), minor::little-integer-unsigned-size(32),
      patch::little-integer-unsigned-size(32)>>
  end

  @impl true
  def decode(value, _) do
    <<major::little-integer-unsigned-size(32), minor::little-integer-unsigned-size(32),
      patch::little-integer-unsigned-size(32), rest::binary>> = value

    {{major, minor, patch}, rest}
  end
end
