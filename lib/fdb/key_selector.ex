defmodule FDB.KeySelector do
  alias FDB.KeySelector

  defstruct [:key, :or_equal, :offset, prefix: :none]

  @type t :: %__MODULE__{
          key: any,
          or_equal: integer(),
          offset: integer(),
          prefix: :none | :first | :last
        }

  @spec last_less_than(any, map()) :: t
  def last_less_than(key, options \\ %{}),
    do: build(key, 0, 0, options)

  @spec last_less_or_equal(any, map) :: t
  def last_less_or_equal(key, options \\ %{}),
    do: build(key, 1, 0, options)

  @spec first_greater_than(any, map) :: t
  def first_greater_than(key, options \\ %{}),
    do: build(key, 1, 1, options)

  @spec first_greater_or_equal(any, map) :: t
  def first_greater_or_equal(key, options \\ %{}),
    do: build(key, 0, 1, options)

  @spec static(any, map) :: t
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
