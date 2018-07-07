defmodule FDB.Error do
  defexception [:message, :code]

  @type t :: %__MODULE__{message: binary, code: integer}
end

defmodule FDB.TimeoutError do
  defexception [:message]

  @type t :: %__MODULE__{message: binary}
end
