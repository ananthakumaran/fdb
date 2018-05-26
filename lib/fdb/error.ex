defmodule FDB.Error do
  defexception [:message, :code]

  @type t :: %__MODULE__{message: binary}
end
