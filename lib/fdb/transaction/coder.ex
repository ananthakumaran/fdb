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
end
