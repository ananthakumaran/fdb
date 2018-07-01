defmodule FDB.Future do
  alias FDB.Native
  alias FDB.Utils

  defstruct resource: nil, on_resolve: []
  @type t :: %__MODULE__{resource: identifier, on_resolve: [(any -> any)]}

  @doc false
  @spec create(identifier) :: t
  def create(resource) do
    %__MODULE__{resource: resource}
  end

  @spec await(t) :: any()
  def await(%__MODULE__{resource: resource, on_resolve: on_resolve}) do
    ref = make_ref()

    :ok =
      Native.future_resolve(resource, ref)
      |> Utils.verify_ok()

    receive do
      {0, ^ref, value} ->
        apply_on_resolve(value, on_resolve)

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    end
  end

  @spec ready?(t) :: boolean
  def ready?(%__MODULE__{resource: resource}) do
    Native.future_is_ready(resource)
  end

  @spec map(t, (any -> any)) :: t
  def map(%__MODULE__{} = future, cb) do
    %{future | on_resolve: [cb | future.on_resolve]}
  end

  defp apply_on_resolve(value, []), do: value
  defp apply_on_resolve(value, [cb]), do: cb.(value)

  defp apply_on_resolve(value, on_resolve) do
    Enum.reverse(on_resolve)
    |> Enum.reduce(value, fn cb, acc -> cb.(acc) end)
  end
end
