defmodule FDB.Coder.Subspace do
  alias FDB.Utils
  @behaviour FDB.Coder.Behaviour

  defmodule Opts do
    defstruct [:prefix, :coder]
  end

  def new(prefix, coder) do
    opts = %Opts{prefix: prefix, coder: coder}

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
  def range(nil, opts), do: {opts.prefix <> <<0x00>>, opts.prefix <> <<0xFF>>}

  def range(value, opts) do
    {s, e} = opts.coder.range(value, opts)
    {opts.prefix <> s, opts.prefix <> e}
  end
end
