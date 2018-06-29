defmodule FDB.KeyRange do
  alias FDB.KeySelector

  defstruct [:begin, :end]

  @type t :: %__MODULE__{begin: KeySelector.t(), end: KeySelector.t()}

  @spec range(any, any, map) :: t
  def range(begin_key, end_key, opts \\ %{}) do
    %__MODULE__{
      begin:
        KeySelector.first_greater_or_equal(begin_key, %{
          prefix: Map.get(opts, :begin_key_prefix, :none)
        }),
      end:
        KeySelector.first_greater_or_equal(end_key, %{
          prefix: Map.get(opts, :end_key_prefix, :none)
        })
    }
  end

  @spec starts_with(any) :: t()
  def starts_with(prefix) do
    %__MODULE__{
      begin: KeySelector.first_greater_or_equal(prefix, %{prefix: :first}),
      end: KeySelector.first_greater_than(prefix, %{prefix: :last})
    }
  end
end
