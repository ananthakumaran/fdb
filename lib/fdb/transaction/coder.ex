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

  def encode_range_start(coder, key) do
    {range_start, _} = coder.key.module.range(key, coder.key.opts)
    range_start
  end

  def encode_range_end(coder, key) do
    {_, range_end} = coder.key.module.range(key, coder.key.opts)
    range_end
  end
end
