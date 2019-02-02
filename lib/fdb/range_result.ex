defmodule FDB.RangeResult do
  defstruct [:key_values, :has_more, :next]

  @type t :: %__MODULE__{
          key_values: [{any(), any()}],
          has_more: boolean(),
          next: (FDB.Transaction.t() -> t)
        }
end
