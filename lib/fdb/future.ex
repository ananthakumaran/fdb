defmodule FDB.Future do
  alias FDB.Native
  alias FDB.Utils
  alias FDB.Future

  defstruct resource: nil, on_resolve: []

  def create(resource) do
    %Future{resource: resource}
  end

  def await(%Future{resource: resource, on_resolve: on_resolve}) do
    ref = make_ref()

    Native.future_resolve(resource, ref)
    |> Utils.verify_result()

    receive do
      {0, ^ref, value} ->
        Enum.reverse(on_resolve)
        |> Enum.reduce(value, fn cb, acc -> cb.(acc) end)

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    end
  end

  def ready?(%Future{resource: resource}) do
    Native.future_is_ready(resource)
  end

  def map(%Future{} = future, cb) do
    %{future | on_resolve: [cb | future.on_resolve]}
  end
end
