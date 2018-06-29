defmodule FDB.KeySelector do
  @moduledoc """
  Refer
  [KeySelector](https://apple.github.io/foundationdb/developer-guide.html#key-selectors)
  section for the semantics. A partial or prefix key could refer to
  multiple keys in the database. The prefix option controls whether it
  should be resolved to the first or last key with the given prefix.

  ### Supported Options

  All the functions in this module support the following options

  * `:or_equal` - (boolean) the default value differs for each function.
  * `:offset` - (integer) could be either positive or negative. Defaults to `0`.
  * `:prefix` - (atom)
    * `:first` - the first key with the given prefix
    * `:last` - the last key with the given prefix
    * `:none` - specifies this is not a prefix key. Default value.

  """
  alias FDB.KeySelector
  alias FDB.Utils

  defstruct [:key, :or_equal, :offset, prefix: :none]

  @type t :: %__MODULE__{
          key: any,
          or_equal: boolean | integer,
          offset: integer,
          prefix: :none | :first | :last
        }

  @spec last_less_than(any, map) :: t
  def last_less_than(key, options \\ %{}),
    do: build(key, false, 0, options)

  @spec last_less_or_equal(any, map) :: t
  def last_less_or_equal(key, options \\ %{}),
    do: build(key, true, 0, options)

  @spec first_greater_than(any, map) :: t
  def first_greater_than(key, options \\ %{}),
    do: build(key, true, 1, options)

  @spec first_greater_or_equal(any, map) :: t
  def first_greater_or_equal(key, options \\ %{}),
    do: build(key, false, 1, options)

  defp build(key, or_equal, offset, options) do
    offset = offset + Map.get(options, :offset, 0)

    %KeySelector{
      key: key,
      offset: offset,
      or_equal: Utils.normalize_bool(Map.get(options, :or_equal, or_equal)),
      prefix: Map.get(options, :prefix, :none)
    }
  end
end
