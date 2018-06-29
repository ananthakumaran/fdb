defmodule FDB.KeySelectorRange do
  alias FDB.KeySelector

  defstruct [:begin, :end]
  @type t :: %__MODULE__{begin: KeySelector.t(), end: KeySelector.t()}

  @spec range(KeySelector.t(), KeySelector.t()) :: t
  def range(%KeySelector{} = start_key_selector, %KeySelector{} = end_key_selector) do
    %__MODULE__{begin: start_key_selector, end: end_key_selector}
  end

  @spec starts_with(any) :: t()
  def starts_with(prefix) do
    %__MODULE__{
      begin: KeySelector.first_greater_or_equal(prefix, %{prefix: :first}),
      end: KeySelector.first_greater_than(prefix, %{prefix: :last})
    }
  end
end
