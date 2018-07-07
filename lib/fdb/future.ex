defmodule FDB.Future do
  @moduledoc """
  A `t:FDB.Future.t/0` represents the result of an async operation.
  """
  alias FDB.Native
  alias FDB.Utils

  defstruct resource: nil, on_resolve: []
  @type t :: %__MODULE__{resource: identifier, on_resolve: [(any -> any)]}

  @doc false
  @spec create(identifier) :: t
  def create(resource) do
    %__MODULE__{resource: resource}
  end

  @doc """
  Waits for the async operation associated with the future to
  complete.

  The result of the operations is returned or `FDB.Error` is raised if
  the operation failed. In case of timeout `FDB.TimeoutError` is
  raised.
  """
  @spec await(t, timeout) :: any()
  def await(%__MODULE__{resource: resource, on_resolve: on_resolve}, timeout \\ 5000) do
    ref = make_ref()

    :ok =
      Native.future_resolve(resource, ref)
      |> Utils.verify_ok()

    receive do
      {0, ^ref, value} ->
        apply_on_resolve(value, on_resolve)

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    after
      timeout ->
        raise FDB.TimeoutError, "Operation timed out"
    end
  end

  @doc """
  Checks whether the async operation is completed.

  If the returned value is `true`, any further calls to `await/1` will
  return immediatly.
  """
  @spec ready?(t) :: boolean
  def ready?(%__MODULE__{resource: resource}) do
    Native.future_is_ready(resource)
  end

  @doc """
  Maps the future's result.

  Returns a new future. The callback function will be applied on the
  result of the given future.
  """
  @spec map(t, (any -> any)) :: t
  def map(%__MODULE__{} = future, callback) do
    %{future | on_resolve: [callback | future.on_resolve]}
  end

  defp apply_on_resolve(value, []), do: value
  defp apply_on_resolve(value, [cb]), do: cb.(value)

  defp apply_on_resolve(value, on_resolve) do
    Enum.reverse(on_resolve)
    |> Enum.reduce(value, fn cb, acc -> cb.(acc) end)
  end
end
