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
  end

  def get(transaction, key) do
    Native.transaction_get(transaction, key)
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
  defp verify_result(code), do: raise(FDB.Error, Native.get_error(code))
end
