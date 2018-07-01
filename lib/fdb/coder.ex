defmodule FDB.Coder do
  @moduledoc """
  A `t:FDB.Coder.t/0` specifies how any value should be encoded before
  storing it in server and how it should be decoded when it's
  retrieved from the server. A custom coder can be created by
  implementing the `FDB.Coder.Behaviour` behaviour.
  """
  defstruct [:module, opts: nil]
  @type t :: %__MODULE__{module: module, opts: any}
end
