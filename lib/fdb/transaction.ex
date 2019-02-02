defmodule FDB.Transaction do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.KeySelector
  alias FDB.KeyRange
  alias FDB.KeySelectorRange
  alias FDB.Transaction
  alias FDB.Database
  alias FDB.Transaction.Coder
  alias FDB.Option

  defstruct resource: nil, coder: nil, snapshot: 0
  @type t :: %__MODULE__{resource: identifier, coder: Transaction.Coder.t(), snapshot: integer}

  @doc """
  Creates a new transaction.
  """
  @spec create(Database.t(), map) :: t
  def create(%Database{} = database, defaults \\ %{}) when is_map(defaults) do
    resource =
      Native.database_create_transaction(database.resource)
      |> Utils.verify_result()

    defaults = Utils.normalize_bool_values(defaults, [:snapshot])

    struct!(__MODULE__, Map.take(database, [:coder]))
    |> struct!(defaults)
    |> struct!(%{resource: resource})
  end

  @doc """
  Changes the default options associated with the transaction.
  """
  @spec set_defaults(t, map) :: t
  def set_defaults(%Transaction{} = transaction, defaults) when is_map(defaults) do
    defaults = Utils.normalize_bool_values(defaults, [:snapshot])
    struct!(transaction, defaults)
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `transaction_option_` is allowed.
  """
  @spec set_option(t, Option.key()) :: :ok
  def set_option(%Transaction{} = transaction, option) do
    Option.verify_transaction_option(option)

    Native.transaction_set_option(transaction.resource, option)
    |> Utils.verify_ok()
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `transaction_option_` is allowed.
  """
  @spec set_option(t, Option.key(), Option.value()) :: :ok
  def set_option(%Transaction{} = transaction, option, value) do
    Option.verify_transaction_option(option, value)

    Native.transaction_set_option(transaction.resource, option, Option.normalize_value(value))
    |> Utils.verify_ok()
  end

  @doc """
  Reads a value from the database snapshot represented by transaction.

  If *key* is not present in the database, `nil` is returned as the result.

  ## Options

  * `:snapshot` - (boolean) Defaults to `false`.
  """
  @spec get(t, any, map) :: any
  def get(%Transaction{} = transaction, key, options \\ %{}) when is_map(options) do
    get_q(transaction, key, options)
    |> Future.await()
  end

  @doc """
  Async version of `get/3`
  """
  @spec get_q(t, any, map) :: Future.t()
  def get_q(%Transaction{} = transaction, key, options \\ %{}) when is_map(options) do
    options = Utils.normalize_bool_values(options, [:snapshot])
    coder = Map.get(options, :coder, transaction.coder)

    Native.transaction_get(
      transaction.resource,
      Coder.encode_key(coder, key),
      Map.get(options, :snapshot, transaction.snapshot)
    )
    |> Future.create()
    |> Future.map(&Coder.decode_value(coder, &1))
  end

  defp do_get_range(%Transaction{} = transaction, begin_key_selector, end_key_selector, options) do
    Native.transaction_get_range(
      transaction.resource,
      begin_key_selector.key,
      begin_key_selector.or_equal,
      begin_key_selector.offset,
      end_key_selector.key,
      end_key_selector.or_equal,
      end_key_selector.offset,
      Map.get(options, :limit, 0),
      Map.get(options, :target_bytes, 0),
      Map.get(options, :mode, FDB.Option.streaming_mode_iterator()),
      Map.get(options, :iteration, 1),
      Map.get(options, :snapshot, transaction.snapshot),
      Map.get(options, :reverse, 0)
    )
    |> Future.create()
    |> Future.await()
  end

  defp decode_range_items(coder, items) do
    Enum.map(items, fn {key, value} ->
      key = Coder.decode_key(coder, key)
      value = Coder.decode_value(coder, value)
      {key, value}
    end)
  end

  @doc """
  Reads all key-value pairs in the database snapshot represented by
  transaction which have a key lexicographically greater than or equal
  to the key resolved by the begin key selector and lexicographically
  less than the key resolved by the end key selector.

  Multiple calls may be made to server to fetch the data. The amount
  of data returned on each call is determined by the options like
  `target_bytes` and `mode`.

  A `Stream` is returned which fetches the data lazily. This is
  suitable for iterating over large list of key value pair.

  ## Options

  * `:snapshot` - (boolean) Defaults to `false`.
  * `:reverse` - (boolean) Defaults to `false`.
  * `:target_bytes` - (boolean) If non-zero, indicates a (soft) cap on
    the combined number of bytes of keys and values to return per
    call. Defaults to `0`.
  * `:mode` - (`t:FDB.Option.key/0`) Refer `FDB.Option` for the list
    of options. Any option that starts with `streaming_mode_` is
    allowed. Defaults to `FDB.Option.streaming_mode_iterator/0`.
  * `:limit` - (number) If non-zero, indicates the maximum number of
    key-value pairs to return. Defaults to `0`.
  """
  @spec get_range_stream(t | Database.t(), KeySelectorRange.t(), map) :: Enumerable.t()
  def get_range_stream(
        %{__struct__: struct} = transaction,
        %KeySelectorRange{} = key_selector_range,
        options \\ %{}
      )
      when is_map(options) and struct in [Transaction, Database] do
    database_or_transaction = transaction

    coder = Map.get(options, :coder, database_or_transaction.coder)

    options =
      Utils.normalize_bool_values(options, [:reverse, :snapshot])
      |> Utils.verify_value(:limit, :positive_integer)
      |> Utils.verify_value(:target_bytes, :positive_integer)
      |> Utils.verify_value(:mode, &Option.verify_streaming_mode/1)

    has_limit = Map.has_key?(options, :limit) && options.limit > 0

    begin_key_selector = %{
      key_selector_range.begin
      | key:
          Coder.encode_range(
            coder,
            key_selector_range.begin.key,
            key_selector_range.begin.prefix
          )
    }

    end_key_selector = %{
      key_selector_range.end
      | key:
          Coder.encode_range(
            coder,
            key_selector_range.end.key,
            key_selector_range.end.prefix
          )
    }

    state =
      Map.merge(
        options,
        %{
          limit: Map.get(options, :limit, 0),
          reverse: Map.get(options, :reverse, 0),
          has_more: 1,
          iteration: 1,
          mode: Map.get(options, :mode, FDB.Option.streaming_mode_iterator()),
          begin_key_selector: begin_key_selector,
          end_key_selector: end_key_selector
        }
      )

    Stream.unfold(
      state,
      fn
        %{has_more: 0} ->
          nil

        state ->
          {has_more, list} =
            case database_or_transaction do
              %Database{} ->
                Database.transact(database_or_transaction, fn t ->
                  do_get_range(t, state.begin_key_selector, state.end_key_selector, state)
                end)

              %Transaction{} ->
                do_get_range(
                  database_or_transaction,
                  state.begin_key_selector,
                  state.end_key_selector,
                  state
                )
            end

          limit =
            if has_limit do
              state.limit - length(list)
            else
              0
            end

          has_more =
            if (has_limit && limit <= 0) || Enum.empty?(list) do
              0
            else
              has_more
            end

          {begin_key_selector, end_key_selector} =
            if !Enum.empty?(list) do
              {key, _value} = List.last(list)

              if state.reverse == 0 do
                {KeySelector.first_greater_than(key), end_key_selector}
              else
                {begin_key_selector, KeySelector.first_greater_or_equal(key)}
              end
            else
              {nil, nil}
            end

          {decode_range_items(coder, list),
           %{
             state
             | has_more: has_more,
               limit: limit,
               iteration: state.iteration + 1,
               begin_key_selector: begin_key_selector,
               end_key_selector: end_key_selector
           }}
      end
    )
    |> Stream.flat_map(& &1)
  end

  @doc """
  Returns the transaction snapshot read version.

  The transaction obtains a snapshot read version automatically at the
  time of the first call to `get_*` (including this one) and (unless
  causal consistency has been deliberately compromised by transaction
  options) is guaranteed to represent all transactions which were
  reported committed before that call.
  """
  @spec get_read_version(t) :: integer()
  def get_read_version(%Transaction{} = transaction) do
    get_read_version_q(transaction)
    |> Future.await()
  end

  @doc """
  Async version of `get_read_version/1`
  """
  @spec get_read_version_q(t) :: Future.t()
  def get_read_version_q(%Transaction{} = transaction) do
    Native.transaction_get_read_version(transaction.resource)
    |> Future.create()
  end

  @doc """
  Retrieves the database version number at which a given transaction
  was committed.

  `commit/1` must have been called on transaction and not an error
  before this function is called, or the behavior is
  undefined. Read-only transactions do not modify the database when
  committed and will have a committed version of -1. Keep in mind that
  a transaction which reads keys and then sets them to their current
  values may be optimized to a read-only transaction.

  Note that database versions are not necessarily unique to a given
  transaction and so cannot be used to determine in what order two
  transactions completed. The only use for this function is to
  manually enforce causal consistency when calling
  `set_read_version/2` on another subsequent transaction.

  Most applications will not call this function.
  """
  @spec get_committed_version(t) :: integer()
  def get_committed_version(%Transaction{} = transaction) do
    Native.transaction_get_committed_version(transaction.resource)
    |> Utils.verify_result()
  end

  @doc """
  Returns an `t:FDB.Future.t/0` which will be set to the `t:FDB.Versionstamp.t/0` which was used by any versionstamp operations in this transaction.

  The future will be ready only after the successful completion of a
  call to `commit/1` on this transaction. Read-only transactions do
  not modify the database when committed and will result in the future
  completing with an error. Keep in mind that a transaction which
  reads keys and then sets them to their current values may be
  optimized to a read-only transaction.
  """
  @spec get_versionstamp_q(t) :: Future.t()
  def get_versionstamp_q(%Transaction{} = transaction) do
    Native.transaction_get_versionstamp(transaction.resource)
    |> Future.create()
    |> Future.map(&FDB.Versionstamp.new(&1, 0))
  end

  @doc """
  watch’s behavior is relative to the transaction that created it. A
  watch will report a change in relation to the key’s value as
  readable by that transaction. The initial value used for comparison
  is either that of the transaction’s read version or the value as
  modified by the transaction itself prior to the creation of the
  watch. If the value changes and then changes back to its initial
  value, the watch might not report the change.

  Until the transaction that created it has been committed, a watch
  will not report changes made by other transactions. In contrast, a
  watch will immediately report changes made by the transaction
  itself. Watches cannot be created if the transaction has set the
  `FDB.Option.transaction_option_read_your_writes_disable/0`
  transaction option, and an attempt to do so will return an
  watches_disabled error.

  If the transaction used to create a watch encounters an error during
  commit, then the watch will be set with that error. A transaction
  whose commit result is unknown will set all of its watches with the
  commit_unknown_result error. If an uncommitted transaction is reset
  or destroyed, then any watches it created will be set with the
  transaction_cancelled error.

  Returns an `t:FDB.Future.t/0` representing an empty value that will
  be set once the watch has detected a change to the value at the
  specified key.

  By default, each database connection can have no more than 10,000
  watches that have not yet reported a change. When this number is
  exceeded, an attempt to create a watch will return a
  too_many_watches error. This limit can be changed using the
  `FDB.Option.database_option_max_watches/0` database option.
  """
  @spec watch_q(t, any) :: Future.t()
  def watch_q(%Transaction{} = transaction, key, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    Native.transaction_watch(transaction.resource, Coder.encode_key(coder, key))
    |> Future.create()
  end

  @doc """
  Resolves a key selector against the keys in the database snapshot
  represented by transaction.

  Returns the key in the database matching the key selector.
  """
  @spec get_key(t, KeySelector.t()) :: any
  def get_key(%Transaction{} = transaction, %KeySelector{} = key_selector, options \\ %{})
      when is_map(options) do
    get_key_q(transaction, key_selector, options)
    |> Future.await()
  end

  @doc """
  Async version of `get_key/2`
  """
  @spec get_key_q(t, KeySelector.t()) :: Future.t()
  def get_key_q(%Transaction{} = transaction, %KeySelector{} = key_selector, options \\ %{})
      when is_map(options) do
    options = Utils.normalize_bool_values(options, [:snapshot])
    coder = Map.get(options, :coder, transaction.coder)
    key = Coder.encode_range(coder, key_selector.key, key_selector.prefix)

    Native.transaction_get_key(
      transaction.resource,
      key,
      key_selector.or_equal,
      key_selector.offset,
      Map.get(options, :snapshot, transaction.snapshot)
    )
    |> Future.create()
    |> Future.map(&Coder.decode_key(coder, &1))
  end

  @doc """
  Returns a list of public network addresses as strings, one for each
  of the storage servers responsible for storing key and its
  associated value.
  """
  @spec get_addresses_for_key(t, any) :: [String.t()]
  def get_addresses_for_key(%Transaction{} = transaction, key) do
    get_addresses_for_key_q(transaction, key)
    |> Future.await()
  end

  @doc """
  Async version of `get_addresses_for_key/2`
  """
  @spec get_addresses_for_key_q(t, any) :: Future.t()
  def get_addresses_for_key_q(%Transaction{} = transaction, key, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    Native.transaction_get_addresses_for_key(
      transaction.resource,
      Coder.encode_key(coder, key)
    )
    |> Future.create()
  end

  @doc """
  Modify the database snapshot represented by transaction to change
  the given key to have the given value.

  If the given key was not previously present in the database it is
  inserted. The modification affects the actual database only if
  transaction is later committed with `commit/1`.
  """
  @spec set(t, any, any, map) :: :ok
  def set(%Transaction{} = transaction, key, value, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    Native.transaction_set(
      transaction.resource,
      Coder.encode_key(coder, key),
      Coder.encode_value(coder, value)
    )
    |> Utils.verify_ok()
  end

  @doc """
  Sets the snapshot read version used by a transaction.

  This is not needed in simple cases. If the given version is too old,
  subsequent reads will fail with error_code_past_version; if it is
  too new, subsequent reads may be delayed indefinitely and/or fail
  with error_code_future_version. If any of `get*` have been called on
  this transaction already, the result is undefined.
  """
  @spec set_read_version(t, integer) :: :ok
  def set_read_version(%Transaction{} = transaction, version) when is_integer(version) do
    Native.transaction_set_read_version(transaction.resource, version)
    |> Utils.verify_ok()
  end

  @doc """
  Same as set, but replaces the placeholder versionstamp in the key

  The semantics are same as `set/4` except the key should have one
  incomplete `t:FDB.Versionstamp.t/0`. The versionstamp will get
  replaced on commit of the transaction.

  A transaction is not permitted to read any transformed key or value
  previously set within that transaction, and an attempt to do so will
  result in an error.

  This operation is not compatible with the READ_YOUR_WRITES_DISABLE
  transaction option and will generate an error if used with it.

  > The database version should be atleast 5.2.

  ### Example

      coder =
        FDB.Transaction.Coder.new(
          Coder.Tuple.new({Coder.ByteString.new(), Coder.Versionstamp.new()})
        )

      future =
        Database.transact(db, fn t ->
          :ok =
            Transaction.set_versionstamped_key(
              t,
              {"stamped", FDB.Versionstamp.incomplete()},
              random_value()
            )

          Transaction.get_versionstamp_q(t)
        end)

      stamp = Future.await(future)

      [{{"stamped", key_stamp}, _}] =
        Database.get_range_stream(db, KeySelectorRange.starts_with({"stamped"}))
        |> Enum.to_list()

      assert stamp == key_stamp
  """

  @spec set_versionstamped_key(t, any, any, map) :: :ok
  def set_versionstamped_key(%Transaction{} = transaction, key, value, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    case Coder.encode_key_versionstamped(coder, key) do
      {:ok, encoded} ->
        operation_type = FDB.Option.mutation_type_set_versionstamped_key()
        param = Coder.encode_value(coder, value)
        Option.verify_mutation_type(operation_type, param)

        Native.transaction_atomic_op(
          transaction.resource,
          encoded,
          param,
          operation_type
        )
        |> Utils.verify_ok()

      {:error, 0} ->
        raise ArgumentError, "No incomplete versionstamp found in the key"

      {:error, n} when n > 1 ->
        raise ArgumentError, "More than 1 incomplete versionstamps found in the key"
    end
  end

  @doc """
  Same as set, but replaces the placeholder versionstamp in the value

  The semantics are same as `set/4` except the value should have one
  incomplete `t:FDB.Versionstamp.t/0`. The versionstamp will get
  replaced on commit of the transaction.

  A transaction is not permitted to read any transformed key or value
  previously set within that transaction, and an attempt to do so will
  result in an error.

  This operation is not compatible with the READ_YOUR_WRITES_DISABLE
  transaction option and will generate an error if used with it.

  > The database version should be atleast 5.2.

  ### Example
      coder =
        FDB.Transaction.Coder.new(
          Coder.ByteString.new(),
          Coder.Tuple.new({Coder.ByteString.new(), Coder.Versionstamp.new()})
        )

      future =
        Database.transact(db, fn t ->
          :ok =
            Transaction.set_versionstamped_value(
              t,
              key,
              {"stamped", FDB.Versionstamp.incomplete()}
            )

          Transaction.get_versionstamp_q(t)
        end)

      stamp = Future.await(future)

      value =
        Database.transact(db, fn t ->
          Transaction.get(t, key)
        end)

      assert {"stamped", stamp} == value
  """
  @spec set_versionstamped_value(t, any, any, map) :: :ok
  def set_versionstamped_value(%Transaction{} = transaction, key, value, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    case Coder.encode_value_versionstamped(coder, value) do
      {:ok, param} ->
        operation_type = FDB.Option.mutation_type_set_versionstamped_value()
        Option.verify_mutation_type(operation_type, param)

        Native.transaction_atomic_op(
          transaction.resource,
          Coder.encode_key(coder, key),
          param,
          operation_type
        )
        |> Utils.verify_ok()

      {:error, 0} ->
        raise ArgumentError, "No incomplete versionstamp found in the value"

      {:error, n} when n > 1 ->
        raise ArgumentError, "More than 1 incomplete versionstamps found in the value"
    end
  end

  @doc """
  Modify the database snapshot represented by transaction to perform
  the operation indicated by operation_type with operand param to the
  value stored by the given key.

  An atomic operation is a single database command that carries out
  several logical steps: reading the value of a key, performing a
  transformation on that value, and writing the result. Different
  atomic operations perform different transformations. Like other
  database operations, an atomic operation is used within a
  transaction; however, its use within a transaction will not cause
  the transaction to conflict.

  Atomic operations do not expose the current value of the key to the
  client but simply send the database the transformation to apply. In
  regard to conflict checking, an atomic operation is equivalent to a
  write without a read. It can only cause other transactions
  performing reads of the key to conflict.

  By combining these logical steps into a single, read-free operation,
  FoundationDB can guarantee that the transaction will not conflict
  due to the operation. This makes atomic operations ideal for
  operating on keys that are frequently modified. A common example is
  the use of a key-value pair as a counter.

  > If a transaction uses both an atomic operation and a serializable
    read on the same key, the benefits of using the atomic operation
    (for both conflict checking and performance) are lost.

  The modification affects the actual database only if transaction is
  later committed with `commit/1`.

  Refer `FDB.Option` for the list of operation_type. Any option that
  starts with `mutation_type_` is allowed
  """
  @spec atomic_op(t, any, Option.key(), Option.value()) :: :ok
  def atomic_op(%Transaction{} = transaction, key, operation_type, param, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)
    param = Coder.encode_value(coder, param)
    Option.verify_mutation_type(operation_type, param)

    Native.transaction_atomic_op(
      transaction.resource,
      Coder.encode_key(coder, key),
      param,
      operation_type
    )
    |> Utils.verify_ok()
  end

  @doc """
  Modifies the database snapshot represented by transaction to remove
  the given key from the database. If the key was not previously
  present in the database, there is no effect.

  The modification affects the actual database only if transaction is
  later committed with `commit/1`.
  """
  @spec clear(t, any) :: :ok
  def clear(%Transaction{} = transaction, key, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)

    Native.transaction_clear(transaction.resource, Coder.encode_key(coder, key))
    |> Utils.verify_ok()
  end

  @doc """
  Modify the database snapshot represented by transaction to remove
  all keys (if any) which are lexicographically greater than or equal
  to the given begin key and lexicographically less than the given end
  key.

  The modification affects the actual database only if transaction is
  later committed with `commit/1`.
  """
  @spec clear_range(t, KeyRange.t()) :: :ok
  def clear_range(%Transaction{} = transaction, %KeyRange{} = key_range, options \\ %{}) do
    coder = Map.get(options, :coder, transaction.coder)
    begin_key = Coder.encode_range(coder, key_range.begin.key, key_range.begin.prefix)
    end_key = Coder.encode_range(coder, key_range.end.key, key_range.end.prefix)

    Native.transaction_clear_range(transaction.resource, begin_key, end_key)
    |> Utils.verify_ok()
  end

  @doc """
  Attempts to commit the sets and clears previously applied to the
  database snapshot represented by transaction to the actual
  database. The commit may or may not succeed – in particular, if a
  conflicting transaction previously committed, then the commit must
  fail in order to preserve transactional isolation. If the commit
  does succeed, the transaction is durably committed to the database
  and all subsequently started transactions will observe its effects.

  It is not necessary to commit a read-only transaction.

  As with other client/server databases, in some failure scenarios a
  client may be unable to determine whether a transaction
  succeeded. In these cases, `commit/1` will return a
  commit_unknown_result error. The `FDB.Database.transact/2` function
  treats this error as retryable, so this could execute the
  transaction twice. In these cases, you must consider the idempotence
  of the transaction.

  Normally, commit will wait for outstanding reads to return. However,
  if those reads were snapshot reads or the transaction option for
  `FDB.Option.transaction_option_read_your_writes_disable/0` has been
  invoked, any outstanding reads will immediately return errors.
  """
  @spec commit(t) :: :ok
  def commit(%Transaction{} = transaction) do
    commit_q(transaction)
    |> Future.await()
  end

  @doc """
  Async version of `commit/1`
  """
  @spec commit_q(t) :: Future.t()
  def commit_q(%Transaction{} = transaction) do
    Native.transaction_commit(transaction.resource)
    |> Future.create()
  end

  @doc """
  Cancels the transaction. All pending or future uses of the
  transaction will return a transaction_cancelled error.

  > If your program attempts to cancel a transaction after `commit/1`
    has been called but before it returns, unpredictable behavior will
    result. While it is guaranteed that the transaction will
    eventually end up in a cancelled state, the commit may or may not
    occur. Moreover, even if the call to `commit/1` appears to return
    a transaction_cancelled error, the commit may have occurred or may
    occur in the future. This can make it more difficult to reason
    about the order in which transactions occur.
  """
  @spec cancel(t) :: :ok
  def cancel(%Transaction{} = transaction) do
    Native.transaction_cancel(transaction.resource)
    |> Utils.verify_ok()
  end

  @spec on_error(t, integer) :: :ok
  def on_error(%Transaction{} = transaction, code) when is_integer(code) do
    on_error_q(transaction, code)
    |> Future.await()
  end

  @doc """
  Async version of `on_error/2`
  """
  @spec on_error_q(t, integer) :: Future.t()
  def on_error_q(%Transaction{} = transaction, code) when is_integer(code) do
    Native.transaction_on_error(transaction.resource, code)
    |> Future.create()
  end

  @doc """
  Adds a conflict range to a transaction without performing the
  associated read or write.

  > Most applications will use the serializable isolation that
    transactions provide by default and will not need to manipulate
    conflict ranges.
  """
  @spec add_conflict_range(t, KeyRange.t(), Option.key()) :: :ok
  def add_conflict_range(
        %Transaction{} = transaction,
        %KeyRange{} = key_range,
        type,
        options \\ %{}
      ) do
    Option.verify_conflict_range_type(type)
    coder = Map.get(options, :coder, transaction.coder)

    begin_key = Coder.encode_range(coder, key_range.begin.key, key_range.begin.prefix)
    end_key = Coder.encode_range(coder, key_range.end.key, key_range.end.prefix)

    Native.transaction_add_conflict_range(transaction.resource, begin_key, end_key, type)
    |> Utils.verify_ok()
  end

  def add_conflict_key(%Transaction{} = transaction, key, type, options \\ %{}) do
    Option.verify_conflict_range_type(type)
    coder = Map.get(options, :coder, transaction.coder)

    begin_key = Coder.encode_key(coder, key)
    end_key = begin_key <> <<0x00>>

    Native.transaction_add_conflict_range(transaction.resource, begin_key, end_key, type)
    |> Utils.verify_ok()
  end
end
