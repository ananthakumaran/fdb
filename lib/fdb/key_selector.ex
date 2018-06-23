defmodule FDB.KeySelector do
  alias FDB.KeySelector

  defstruct [:key, :or_equal, :offset, prefix: :none]

  def last_less_than(key, options \\ %{}),
    do: build(key, 0, 0, options)

  def last_less_or_equal(key, options \\ %{}),
    do: build(key, 1, 0, options)

  def first_greater_than(key, options \\ %{}),
    do: build(key, 1, 1, options)

  def first_greater_or_equal(key, options \\ %{}),
    do: build(key, 0, 1, options)

  def static(key, options \\ %{}) do
    first_greater_than(key, options)
  end

  defp build(key, or_equal, offset, options) do
    offset = offset + Map.get(options, :offset, 0)

    %KeySelector{
      key: key,
      offset: offset,
      or_equal: Map.get(options, :or_equal, or_equal),
      prefix: Map.get(options, :prefix, :none)
    }
  end
end
