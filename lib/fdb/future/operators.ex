defmodule FDB.Future.Operators do
  def @future, do: FDB.Future.resolve(future)

  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [@: 1]
      import unquote(__MODULE__)
    end
  end
end
