defmodule FDB.Transaction.Coder do
  defstruct key: FDB.Coder.Identity.new(), value: FDB.Coder.Identity.new()

  def encode_key(coder, key) do
    coder.key.module.encode(key, coder.key.opts)
  end

  def decode_key(coder, key) do
    {value, <<>>} = coder.key.module.decode(key, coder.key.opts)
    value
  end

  def encode_value(coder, key) do
    coder.value.module.encode(key, coder.value.opts)
  end

  def decode_value(coder, key) do
    {value, <<>>} = coder.value.module.decode(key, coder.value.opts)
    value
  end

  def encode_range(coder, key, :none) do
    encode_key(coder, key)
  end

  def encode_range(coder, key, :first) do
    {value, _} = coder.key.module.range(key, coder.key.opts)
    value <> <<0x00>>
  end

  def encode_range(coder, key, :last) do
    {value, _} = coder.key.module.range(key, coder.key.opts)
    value <> <<0xFF>>
  end
end
