defmodule FDB.Coder.Subspace do
  alias FDB.Utils
  alias FDB.Directory
  use FDB.Coder.Behaviour

  defmodule Opts do
    @moduledoc false

    defstruct [:prefix, :coder]
  end

  @doc """
  Creates a new subspace.
  The prefix can be provided in three ways

  * raw binary
  * {prefix_value, prefix_coder} - a value and a coder to encode the value
  * a directory
  """
  @spec new(binary | {any, FDB.Coder.t()} | Directory.t(), FDB.Coder.t()) :: FDB.Coder.t()
  def new(prefix, coder \\ FDB.Coder.Identity.new())

  def new({prefix_value, prefix_coder}, coder) do
    prefix = prefix_coder.module.encode(prefix_value, prefix_coder.opts)
    create(prefix, coder)
  end

  def new(prefix, coder) when is_binary(prefix) do
    create(prefix, coder)
  end

  def new(%FDB.Coder{module: __MODULE__} = subspace, coder) do
    create(subspace.opts.prefix, coder)
  end

  def new(directory, coder) do
    create(Directory.prefix(directory), coder)
  end

  @doc """
  Concats two subspaces. The coder associated with `a` will be discarded.
  """
  @spec concat(FDB.Coder.t(), FDB.Coder.t()) :: FDB.Coder.t()
  def concat(a, b) do
    opts = %Opts{prefix: a.opts.prefix <> b.opts.prefix, coder: b.opts.coder}

    %FDB.Coder{
      module: __MODULE__,
      opts: opts
    }
  end

  defp create(prefix, coder) do
    %FDB.Coder{
      module: __MODULE__,
      opts: %Opts{prefix: prefix, coder: coder}
    }
  end

  @impl true
  def encode(value, opts) do
    coder = opts.coder
    opts.prefix <> coder.module.encode(value, coder.opts)
  end

  @impl true
  def decode(value, opts) do
    coder = opts.coder
    prefix = opts.prefix
    {^prefix, rest} = Utils.binary_cut(value, byte_size(prefix))
    coder.module.decode(rest, coder.opts)
  end

  @impl true
  def range(nil, opts), do: {opts.prefix, <<>>}

  def range(value, opts) do
    {prefix, suffix} = opts.coder.module.range(value, opts.coder.opts)
    {opts.prefix <> prefix, suffix}
  end
end
