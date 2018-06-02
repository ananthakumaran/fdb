defmodule FDB.Database do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Database

  defstruct resource: nil, coder: nil

  def create(cluster, coder \\ %FDB.Transaction.Coder{}) do
    resource =
      Native.cluster_create_database(cluster)
      |> Future.resolve()

    %Database{resource: resource, coder: coder}
  end

  def set_coder(db, coder) do
    %{db | coder: coder}
  end

  def set_option(database, option) do
    Native.database_set_option(database.resource, option)
    |> Utils.verify_result()
  end

  def set_option(database, option, value) do
    Native.database_set_option(database.resource, option, value)
    |> Utils.verify_result()
  end
end
