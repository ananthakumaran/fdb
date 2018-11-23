defmodule FDB.Transaction.Coder do
  @moduledoc """
  A `t:FDB.Transaction.Coder.t/0` specifies how the key and value should be encoded.
  """

  alias FDB.Coder
  alias FDB.Coder.Identity
  alias FDB.Versionstamp

  defstruct key: Identity.new(), value: Identity.new()

  @type t :: %__MODULE__{key: Coder.t(), value: Coder.t()}

  @doc """
  Creates a new `t:FDB.Transaction.Coder.t/0`
  """
  @spec new(Coder.t(), Coder.t()) :: t
  def new(key_coder \\ Identity.new(), value_coder \\ Identity.new()) do
    %__MODULE__{key: key_coder, value: value_coder}
  end

  @doc false
  @spec encode_key(t, any) :: binary
  def encode_key(%__MODULE__{key: %Coder{module: module, opts: opts}}, key) do
    module.encode(key, opts)
  end

  @doc false
  @spec encode_key_versionstamped(t, any) :: {:ok, binary} | {:error, integer}
  def encode_key_versionstamped(%__MODULE__{key: coder}, key) do
    encode_versionstamped(coder, key)
  end

  @doc false
  @spec decode_key(t, binary) :: any
  def decode_key(%__MODULE__{key: %Coder{module: module, opts: opts}}, key) do
    {value, <<>>} = module.decode(key, opts)
    value
  end

  @doc false
  @spec encode_value(t, any) :: binary
  def encode_value(%__MODULE__{value: %Coder{module: module, opts: opts}}, key) do
    module.encode(key, opts)
  end

  @doc false
  @spec encode_value_versionstamped(t, any) :: {:ok, binary} | {:error, integer}
  def encode_value_versionstamped(%__MODULE__{value: coder}, value) do
    encode_versionstamped(coder, value)
  end

  @doc false
  @spec decode_value(t, binary) :: any
  def decode_value(_, nil), do: nil

  def decode_value(%__MODULE__{value: %Coder{module: module, opts: opts}}, value) do
    {value, <<>>} = module.decode(value, opts)
    value
  end

  @doc false
  @spec encode_range(t, any, :none | :first | :last) :: binary
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

  defp traverse(%Versionstamp{} = v, cb) do
    if Versionstamp.incomplete?(v) do
      {1, cb.(v)}
    else
      {0, v}
    end
  end

  defp traverse(value, cb) when is_tuple(value) do
    {count, list} = traverse(Tuple.to_list(value), cb)
    {count, List.to_tuple(list)}
  end

  defp traverse(value, cb) when is_map(value) do
    {count, list} = traverse(Map.to_list(value), cb)
    {count, Enum.into(list, %{})}
  end

  defp traverse(value, cb) when is_list(value) do
    {count, list} =
      Enum.reduce(value, {0, []}, fn item, {count, list} ->
        {c, item} = traverse(item, cb)
        {count + c, [item | list]}
      end)

    {count, Enum.reverse(list)}
  end

  defp traverse(value, _cb), do: {0, value}

  defp encode_versionstamped(%Coder{module: module, opts: opts} = coder, value) do
    marker = :crypto.strong_rand_bytes(10)

    {count, transformed_value} =
      traverse(value, &Versionstamp.new(marker, Versionstamp.user_version(&1)))

    if count != 1 do
      {:error, count}
    else
      encoded = module.encode(transformed_value, opts)
      {start, 10} = :binary.match(encoded, marker)

      case :binary.match(encoded, marker, [{:scope, {start + 1, 10}}]) do
        :nomatch ->
          {:ok, encoded <> <<start::unsigned-little-integer-size(32)>>}

        _ ->
          encode_versionstamped(coder, value)
      end
    end
  end
end
