defmodule FDB.Database do
  @moduledoc """
  This module provides functions to create and configure database and
  functions to do transactions on database.
  """
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Cluster
  alias FDB.Option
  alias FDB.Transaction
  alias FDB.KeySelectorRange

  defstruct resource: nil, coder: nil

  @type t :: %__MODULE__{}

  @doc """
  Creates a new database.
  """
  @spec create(Cluster.t()) :: t
  @spec create(Cluster.t(), Transaction.Coder.t()) :: t
  def create(%Cluster{} = cluster, coder \\ Transaction.Coder.new()) do
    create_q(cluster, coder)
    |> Future.await()
  end

  @doc """
  Async version of `create/2`
  """
  @spec create_q(Cluster.t(), Transaction.Coder.t()) :: Future.t()
  def create_q(%Cluster{} = cluster, coder \\ Transaction.Coder.new()) do
    Native.cluster_create_database(cluster.resource)
    |> Future.create()
    |> Future.map(&%__MODULE__{resource: &1, coder: coder})
  end

  @doc """
  Changes the `t:FDB.Transaction.Coder.t/0` associated with the database.

  This doesn't create a new database resource, the same database
  resource is shared. This is the recommended way if one needs to use
  multiple coders.

      db = FDB.Database.create(cluster)
      user_db = FDB.Database.set_coder(db, user_coder)
      comments_db = FDB.Database.set_coder(db, comment_coder)
  """
  @spec set_coder(t, Transaction.Coder.t()) :: t
  def set_coder(%__MODULE__{} = db, coder) do
    %{db | coder: coder}
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `database_option_` is allowed.
  """
  @spec set_option(t, Option.key()) :: :ok
  def set_option(%__MODULE__{} = database, option) do
    Option.verify_database_option(option)

    Native.database_set_option(database.resource, option)
    |> Utils.verify_ok()
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `database_option_` is allowed.
  """
  @spec set_option(t, Option.key(), Option.value()) :: :ok
  def set_option(%__MODULE__{} = database, option, value) do
    Option.verify_database_option(option, value)

    Native.database_set_option(database.resource, option, Option.normalize_value(value))
    |> Utils.verify_ok()
  end

  @doc """
  Refer `FDB.Transaction.get_range/3`. The only difference is the
  consistency guarantee. This function uses multiple transactions to
  fetch the data. This is advantageous if you want to fetch large
  amount of data and are ok with the fact that the data might change
  when doing the iteration.
  """
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

  @doc """
  The given `callback` will be called with a
  `t:FDB.Transaction.t/0`.

  The transaction is automatically committed after the callback
  returns. The value returned by the callback is retuned. In case any
  exception is raised inside the callback or in the commit function
  call, the transaction will be retried if the error is retriable. It
  also implements an exponential backoff strategy to avoid swamping
  the database cluster with excessive retries when there is a high
  level of conflict between transactions.

  Avoid doing any IO or any action that will cause side effect inside
  the `callback`, as the `callback` might get called multiple times in
  case of errors.

  Various options like
  `FDB.Option.transaction_option_max_retry_delay/0`,
  `FDB.Option.transaction_option_timeout/0`,
  `FDB.Option.transaction_option_retry_limit/0` etc which control the
  retry behaviour can be configured using
  `FDB.Transaction.set_option/3`
  """
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
