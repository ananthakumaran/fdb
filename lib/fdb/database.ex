defmodule FDB.Database do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Cluster
  alias FDB.Option
  alias FDB.Transaction
  alias FDB.KeySelectorRange

  defstruct resource: nil, coder: nil

  @type t :: %__MODULE__{}

  @spec create(Cluster.t()) :: t
  @spec create(Cluster.t(), Transaction.Coder.t()) :: t
  def create(%Cluster{} = cluster, coder \\ %Transaction.Coder{}) do
    create_q(cluster, coder)
    |> Future.await()
  end

  @spec create_q(Cluster.t(), Transaction.Coder.t()) :: Future.t()
  def create_q(%Cluster{} = cluster, coder \\ %FDB.Transaction.Coder{}) do
    Native.cluster_create_database(cluster.resource)
    |> Future.create()
    |> Future.map(&%__MODULE__{resource: &1, coder: coder})
  end

  @spec set_coder(t, Transaction.Coder.t()) :: t
  def set_coder(%__MODULE__{} = db, coder) do
    %{db | coder: coder}
  end

  @spec set_option(t, Option.key()) :: :ok
  def set_option(%__MODULE__{} = database, option) do
    Option.verify_database_option(option)

    Native.database_set_option(database.resource, option)
    |> Utils.verify_ok()
  end

  @spec set_option(t, Option.key(), Option.value()) :: :ok
  def set_option(%__MODULE__{} = database, option, value) do
    Option.verify_database_option(option, value)

    Native.database_set_option(database.resource, option, Option.normalize_value(value))
    |> Utils.verify_ok()
  end

  @spec get_range(t, KeySelectorRange.t(), map) :: Enumerable.t()
  def get_range(
        %__MODULE__{} = database,
        %KeySelectorRange{} = key_range,
        options \\ %{}
      ) do
    Transaction.get_range(
      database,
      key_range,
      options
    )
  end

  @spec transact(t, (Transaction.t() -> any)) :: any
  def transact(%__MODULE__{} = database, callback) when is_function(callback) do
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
