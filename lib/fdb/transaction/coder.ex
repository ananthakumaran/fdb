defmodule FDB.Transaction.Coder do
  alias FDB.Coder
  alias FDB.Coder.Identity

  defstruct key: Identity.new(), value: Identity.new()

  @type t :: %__MODULE__{key: Coder.t(), value: Coder.t()}

  @spec new(Coder.t(), Coder.t()) :: t
  def new(key_coder \\ Identity.new(), value_coder \\ Identity.new()) do
    %__MODULE__{key: key_coder, value: value_coder}
  end

  @doc false
  @spec encode_key(t, any) :: any
  def encode_key(%__MODULE__{key: %Coder{module: module, opts: opts}}, key) do
    module.encode(key, opts)
  end

  @doc false
  @spec decode_key(t, any) :: any
  def decode_key(%__MODULE__{key: %Coder{module: module, opts: opts}}, key) do
    {value, <<>>} = module.decode(key, opts)
    value
  end

  @doc false
  @spec encode_value(t, any) :: any
  def encode_value(%__MODULE__{value: %Coder{module: module, opts: opts}}, key) do
    module.encode(key, opts)
  end

  @doc false
  @spec decode_value(t, any) :: any
  def decode_value(%__MODULE__{value: %Coder{module: module, opts: opts}}, key) do
    {value, <<>>} = module.decode(key, opts)
    value
  end

  @doc false
  @spec encode_range(t, any, :none | :first | :last) :: any
  def encode_range(coder, key, :none) do
    encode_key(coder, key)
  end

  def encode_range(%__MODULE__{key: %Coder{module: module, opts: opts}}, key, :first) do
    {value, _} = module.range(key, opts)
    value <> <<0x00>>
  end

  def encode_range(%__MODULE__{key: %Coder{module: module, opts: opts}}, key, :last) do
    {value, _} = module.range(key, opts)
    value <> <<0xFF>>
  end
end
