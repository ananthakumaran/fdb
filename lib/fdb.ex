defmodule FDB do
  alias FDB.Raw

  def init do
    Raw.select_api_version_impl(510, 510)
    Raw.setup_network()
    Raw.run_network()
  end

  def create_cluster do
    Raw.create_cluster()
    |> resolve
  end

  def create_database(cluster) do
    Raw.cluster_create_database(cluster)
    |> resolve
  end

  def create_transaction(database) do
    Raw.database_create_transaction(database)
  end

  def get(transaction, key) do
    Raw.transaction_get(transaction, key)
    |> resolve
  end

  defp resolve(future) do
    Raw.future_resolve(future)
    receive do
      value -> value
    end
  end
end
