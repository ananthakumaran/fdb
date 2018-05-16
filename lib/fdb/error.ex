defmodule FDB.Error do
  defexception [:message]

  @type t :: %__MODULE__{message: binary}
end
