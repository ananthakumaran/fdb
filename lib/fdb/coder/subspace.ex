defmodule FDB.Coder.Subspace do
  alias FDB.Utils
  use FDB.Coder.Behaviour

  defmodule Opts do
    @moduledoc false

    defstruct [:prefix, :coder]
  end

  @spec new(any, FDB.Coder.t(), FDB.Coder.t()) :: FDB.Coder.t()
  def new(prefix, coder \\ FDB.Coder.Identity.new(), prefix_coder \\ FDB.Coder.Identity.new()) do
    prefix = prefix_coder.module.encode(prefix, prefix_coder.opts)
    opts = %Opts{prefix: prefix, coder: coder}

    %FDB.Coder{
      module: __MODULE__,
      opts: opts
    }
  end

  def concat(a, b) do
    opts = %Opts{prefix: a.opts.prefix <> b.opts.prefix, coder: b.opts.coder}

    %FDB.Coder{
      module: __MODULE__,
      opts: opts
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
