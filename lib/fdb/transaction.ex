defmodule FDB.Transaction do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.KeySelector
  alias FDB.Transaction
  alias FDB.Transaction.Coder

  defstruct resource: nil, coder: nil

  def create(database, coder \\ nil) do
    resource =
      Native.database_create_transaction(database.resource)
      |> Utils.verify_result()

    coder =
      if coder do
        coder
      else
        database.coder
      end

    %Transaction{resource: resource, coder: coder}
  end

  def set_option(transaction, option) do
    Native.transaction_set_option(transaction.resource, option)
    |> Utils.verify_result()
  end

  def set_option(transaction, option, value) do
    Native.transaction_set_option(transaction.resource, option, value)
    |> Utils.verify_result()
  end

  def get(transaction, key) do
    v =
      Native.transaction_get(transaction.resource, Coder.encode_key(transaction.coder, key), 0)
      |> Future.resolve()

    Coder.decode_value(transaction.coder, v)
  end

  def get_range(transaction, begin_key_selector, end_key_selector, options \\ %{}) do
    {begin_key, begin_or_equal, begin_offset} = begin_key_selector
    {end_key, end_or_equal, end_offset} = end_key_selector

    Native.transaction_get_range(
      transaction.resource,
      begin_key,
      begin_or_equal,
      begin_offset,
      end_key,
      end_or_equal,
      end_offset,
      Map.get(options, :limit, 0),
      Map.get(options, :target_bytes, 0),
      Map.get(options, :mode, FDB.Option.streaming_mode_iterator()),
      Map.get(options, :iteration, 1),
      Map.get(options, :snapshot, 0),
      Map.get(options, :reverse, 0)
    )
    |> Future.resolve()
  end

  def get_range_stream(database, begin_key_selector, end_key_selector, options \\ %{}) do
    has_limit = Map.has_key?(options, :limit)

    state =
      Map.merge(
        options,
        %{
          limit: Map.get(options, :limit, 0),
          reverse: Map.get(options, :reverse, 0),
          has_more: 1,
          iteration: 1,
          mode: FDB.Option.streaming_mode_iterator(),
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
          t = create(database)

          {has_more, list} = get_range(t, state.begin_key_selector, state.end_key_selector, state)

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

          {list,
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

  def get_snapshot(transaction, key) do
    v =
      Native.transaction_get(transaction.resource, Coder.encode_key(transaction.coder, key), 1)
      |> Future.resolve()

    Coder.decode_value(transaction.coder, v)
  end

  def get_read_version(transaction) do
    Native.transaction_get_read_version(transaction.resource)
    |> Future.resolve()
  end

  def get_committed_version(transaction) do
    Native.transaction_get_committed_version(transaction.resource)
    |> Utils.verify_result()
  end

  def get_versionstamp(transaction) do
    Native.transaction_get_versionstamp(transaction.resource)
  end

  def watch(transaction, key) do
    Native.transaction_watch(transaction.resource, Coder.encode_key(transaction.coder, key))
  end

  def get_key(transaction, key_selector, snapshot \\ 0) do
    {key, or_equal, offset} = key_selector

    k =
      Native.transaction_get_key(transaction.resource, key, or_equal, offset, snapshot)
      |> Future.resolve()

    Coder.decode_key(transaction.coder, k)
  end

  def get_addresses_for_key(transaction, key) do
    Native.transaction_get_addresses_for_key(
      transaction.resource,
      Coder.encode_key(transaction.coder, key)
    )
    |> Future.resolve()
  end

  def set(transaction, key, value) do
    Native.transaction_set(
      transaction.resource,
      Coder.encode_key(transaction.coder, key),
      Coder.encode_value(transaction.coder, value)
    )
    |> Utils.verify_result()
  end

  def set_read_version(transaction, version) do
    Native.transaction_set_read_version(transaction.resource, version)
    |> Utils.verify_result()
  end

  def atomic_op(transaction, key, value, op) do
    Native.transaction_atomic_op(
      transaction.resource,
      Coder.encode_key(transaction.coder, key),
      value,
      op
    )
    |> Utils.verify_result()
  end

  def clear(transaction, key) do
    Native.transaction_clear(transaction.resource, Coder.encode_key(transaction.coder, key))
    |> Utils.verify_result()
  end

  def clear_range(transaction, begin_key, end_key) do
    Native.transaction_clear_range(transaction.resource, begin_key, end_key)
    |> Utils.verify_result()
  end

  def commit(transaction) do
    Native.transaction_commit(transaction.resource)
    |> Future.resolve()
  end

  def transact(database, callback) do
    transaction = create(database)
    result = callback.(transaction)
    :ok = commit(transaction)
    result
  rescue
    e in FDB.Error ->
      if Native.get_error_predicate(FDB.Option.error_predicate_retryable(), e.code) do
        transact(database, callback)
      else
        raise e
      end
  end
end
