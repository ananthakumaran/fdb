defmodule FDB.Coder do
  defstruct [:module, opts: nil]
  @type t :: %__MODULE__{module: module, opts: any}
end
