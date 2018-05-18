defmodule FDB do
  alias FDB.Native

  def start do
    Native.select_api_version_impl(510, 510)
    |> verify_result

    Native.setup_network()
    |> verify_result

    Native.run_network()
    |> verify_result
  end

  def stop do
    Native.stop_network()
    |> verify_result
  end

  def create_cluster do
    Native.create_cluster()
    |> resolve
  end

  def create_database(cluster) do
    Native.cluster_create_database(cluster)
    |> resolve
  end

  def create_transaction(database) do
    Native.database_create_transaction(database)
    |> verify_result
  end

  def get(transaction, key) do
    Native.transaction_get(transaction, key, 0)
    |> resolve
  end

  def get_snapshot(transaction, key) do
    Native.transaction_get(transaction, key, 1)
    |> resolve
  end

  def set(transaction, key, value) do
    Native.transaction_set(transaction, key, value)
    |> verify_result
  end

  def clear(transaction, key) do
    Native.transaction_clear(transaction, key)
    |> verify_result
  end

  def commit(transaction) do
    Native.transaction_commit(transaction)
    |> resolve
  end

  def resolve(future) do
    ref = make_ref()

    Native.future_resolve(future, ref)
    |> verify_result

    receive do
      {0, ^ref, value} -> value
      {error_code, ^ref, nil} -> raise FDB.Error, Native.get_error(error_code)
    end
  end

  defp verify_result(0), do: :ok
  defp verify_result({0, result}), do: result
  defp verify_result(code) when is_integer(code), do: raise(FDB.Error, Native.get_error(code))

  defp verify_result({code, _}) when is_integer(code),
    do: raise(FDB.Error, Native.get_error(code))
end
