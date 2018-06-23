defmodule FDB.Database do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Database
  alias FDB.Cluster
  alias FDB.Option
  alias FDB.Transaction
  alias FDB.KeyRange

  defstruct resource: nil, coder: nil

  def create(%Cluster{} = cluster, coder \\ %FDB.Transaction.Coder{}) do
    create_q(cluster, coder)
    |> Future.resolve()
  end

  def create_q(%Cluster{} = cluster, coder \\ %FDB.Transaction.Coder{}) do
    Native.cluster_create_database(cluster.resource)
    |> Future.map(&%Database{resource: &1, coder: coder})
  end

  def set_coder(%Database{} = db, coder) do
    %{db | coder: coder}
  end

  def set_option(%Database{} = database, option) do
    Option.verify_database_option(option)

    Native.database_set_option(database.resource, option)
    |> Utils.verify_result()
  end

  def set_option(%Database{} = database, option, value) do
    Option.verify_database_option(option, value)

    Native.database_set_option(database.resource, option, Option.normalize_value(value))
    |> Utils.verify_result()
  end

  def get_range_stream(
        %Database{} = database,
        %KeyRange{} = key_range,
        options \\ %{}
      ) do
    Transaction.get_range_stream(
      database,
      key_range,
      options
    )
  end

  def transact(%Database{} = database, callback) do
    do_transact(Transaction.create(database), callback)
  end

  defp do_transact(%Transaction{} = transaction, callback) do
    result = callback.(transaction)
    :ok = Transaction.commit(transaction)
    result
  rescue
    e in FDB.Error ->
      :ok = Transaction.on_error(transaction, e.code)
      do_transact(transaction, callback)
  end
end
