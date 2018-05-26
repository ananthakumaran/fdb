defmodule FDB.Database do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils

  def create(cluster) do
    Native.cluster_create_database(cluster)
    |> Future.resolve()
  end

  def set_option(database, option) do
    Native.database_set_option(database, option)
    |> Utils.verify_result()
  end

  def set_option(database, option, value) do
    Native.database_set_option(database, option, value)
    |> Utils.verify_result()
  end
end
