defmodule FDB.Future do
  @moduledoc """
  A `t:FDB.Future.t/0` represents the result of an async operation.
  """
  alias FDB.Native
  alias FDB.Utils

  defstruct resource: nil, on_resolve: [], waiting_for: [], constant: false, value: nil
  @type t :: %__MODULE__{resource: identifier, on_resolve: [(any -> any)]}

  @doc false
  @spec create(identifier) :: t
  def create(resource) do
    %__MODULE__{resource: resource, waiting_for: [resource]}
  end

  @spec constant(any) :: t
  def constant(value) do
    %__MODULE__{value: value, waiting_for: [], constant: true}
  end

  @doc """
  Waits for the async operation associated with the future to
  complete.

  The result of the operations is returned or `FDB.Error` is raised if
  the operation failed. In case of timeout `FDB.TimeoutError` is
  raised.
  """
  @spec await(t, timeout) :: any()
  def await(future, timeout \\ 5000)

  def await(%__MODULE__{value: value, constant: true, on_resolve: on_resolve}, timeout) do
    apply_on_resolve(value, on_resolve, timeout)
  end

  def await(%__MODULE__{resource: resource, on_resolve: on_resolve}, timeout) do
    ref = make_ref()

    :ok =
      Native.future_resolve(resource, ref)
      |> Utils.verify_ok()

    receive do
      {0, ^ref, value} ->
        apply_on_resolve(value, on_resolve, timeout)

      {error_code, ^ref, nil} ->
        raise FDB.Error, code: error_code, message: Native.get_error(error_code)
    after
      timeout ->
        raise FDB.TimeoutError, "Operation timed out"
    end
  end

  @doc """
  Checks whether the async operation is completed.

  If the future is constructed via `Future.then/3`, then only the root
  future is checked for completion.
  """
  @spec ready?(t) :: boolean
  def ready?(%__MODULE__{waiting_for: waiting_for}) do
    Enum.all?(waiting_for, &Native.future_is_ready/1)
  end

  @doc """
  Maps the future's result.

  Returns a new future. The callback function will be applied on the
  result of the given future.
  """
  @spec map(t, (any -> any)) :: t
  def map(future, callback) do
    then(future, fn x ->
      constant(callback.(x))
    end)
  end

  @spec then(t, (any -> t)) :: t
  def then(%__MODULE__{} = future, callback) do
    cb = fn x, timeout ->
      case callback.(x) do
        %__MODULE__{} = future ->
          await(future, timeout)

        other ->
          other
      end
    end

    %{future | on_resolve: [cb | future.on_resolve]}
  end

  @spec all([t]) :: t
  def all([]), do: constant([])

  def all([head | tail]) do
    then(head, fn x ->
      map(all(tail), &[x | &1])
    end)
  end

  defp apply_on_resolve(value, [], _), do: value
  defp apply_on_resolve(value, [cb], timeout), do: cb.(value, timeout)

  defp apply_on_resolve(value, on_resolve, timeout) do
    Enum.reverse(on_resolve)
    |> Enum.reduce(value, fn cb, acc -> cb.(acc, timeout) end)
  end
end
