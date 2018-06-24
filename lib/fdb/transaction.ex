defmodule FDB.Transaction do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.KeySelector
  alias FDB.KeyRange
  alias FDB.Transaction
  alias FDB.Database
  alias FDB.Transaction.Coder
  alias FDB.Option

  defstruct resource: nil, coder: nil

  def create(%Database{} = database, coder \\ nil) do
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

  def set_coder(%Transaction{} = transaction, coder) do
    %{transaction | coder: coder}
  end

  def set_option(%Transaction{} = transaction, option) do
    Option.verify_transaction_option(option)

    Native.transaction_set_option(transaction.resource, option)
    |> Utils.verify_result()
  end

  def set_option(%Transaction{} = transaction, option, value) do
    Option.verify_transaction_option(option, value)

    Native.transaction_set_option(transaction.resource, option, Option.normalize_value(value))
    |> Utils.verify_result()
  end

  def get(%Transaction{} = transaction, key, options \\ %{}) when is_map(options) do
    get_q(transaction, key, options)
    |> Future.await()
  end

  def get_q(%Transaction{} = transaction, key, options \\ %{}) when is_map(options) do
    options = Utils.normalize_bool_values(options, [:snapshot])

    Native.transaction_get(
      transaction.resource,
      Coder.encode_key(transaction.coder, key),
      Map.get(options, :snapshot, 0)
    )
    |> Future.create()
    |> Future.map(&Coder.decode_value(transaction.coder, &1))
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
      Map.get(options, :snapshot, 0),
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

  def get_range(
        %{__struct__: struct} = transaction,
        %KeyRange{} = key_range,
        options \\ %{}
      )
      when is_map(options) and struct in [Transaction, Database] do
    database_or_transaction = transaction

    options =
      Utils.normalize_bool_values(options, [:reverse, :snapshot])
      |> Utils.verify_value(:limit, :positive_integer)
      |> Utils.verify_value(:target_bytes, :positive_integer)
      |> Utils.verify_value(:mode, &Option.verify_streaming_mode/1)

    has_limit = Map.has_key?(options, :limit) && options.limit > 0

    begin_key_selector = %{
      key_range.begin
      | key:
          Coder.encode_range(
            database_or_transaction.coder,
            key_range.begin.key,
            key_range.begin.prefix
          )
    }

    end_key_selector = %{
      key_range.end
      | key:
          Coder.encode_range(
            database_or_transaction.coder,
            key_range.end.key,
            key_range.end.prefix
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

          {decode_range_items(database_or_transaction.coder, list),
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

  def get_snapshot(%Transaction{} = transaction, key) do
    get_snapshot_q(transaction, key)
    |> Future.await()
  end

  def get_snapshot_q(%Transaction{} = transaction, key) do
    Native.transaction_get(transaction.resource, Coder.encode_key(transaction.coder, key), 1)
    |> Future.create()
    |> Future.map(&Coder.decode_value(transaction.coder, &1))
  end

  def get_read_version(%Transaction{} = transaction) do
    get_read_version_q(transaction)
    |> Future.await()
  end

  def get_read_version_q(%Transaction{} = transaction) do
    Native.transaction_get_read_version(transaction.resource)
    |> Future.create()
  end

  def get_committed_version(%Transaction{} = transaction) do
    Native.transaction_get_committed_version(transaction.resource)
    |> Utils.verify_result()
  end

  def get_versionstamp_q(%Transaction{} = transaction) do
    Native.transaction_get_versionstamp(transaction.resource)
    |> Future.create()
  end

  def watch_q(%Transaction{} = transaction, key) do
    Native.transaction_watch(transaction.resource, Coder.encode_key(transaction.coder, key))
    |> Future.create()
  end

  def get_key(%Transaction{} = transaction, %KeySelector{} = key_selector, options \\ %{})
      when is_map(options) do
    get_key_q(transaction, key_selector, options)
    |> Future.await()
  end

  def get_key_q(%Transaction{} = transaction, %KeySelector{} = key_selector, options \\ %{})
      when is_map(options) do
    options = Utils.normalize_bool_values(options, [:snapshot])
    key = Coder.encode_range(transaction.coder, key_selector.key, key_selector.prefix)

    Native.transaction_get_key(
      transaction.resource,
      key,
      key_selector.or_equal,
      key_selector.offset,
      Map.get(options, :snapshot, 0)
    )
    |> Future.create()
    |> Future.map(&Coder.decode_key(transaction.coder, &1))
  end

  def get_addresses_for_key(%Transaction{} = transaction, key) do
    get_addresses_for_key_q(transaction, key)
    |> Future.await()
  end

  def get_addresses_for_key_q(%Transaction{} = transaction, key) do
    Native.transaction_get_addresses_for_key(
      transaction.resource,
      Coder.encode_key(transaction.coder, key)
    )
    |> Future.create()
  end

  def set(%Transaction{} = transaction, key, value) do
    Native.transaction_set(
      transaction.resource,
      Coder.encode_key(transaction.coder, key),
      Coder.encode_value(transaction.coder, value)
    )
    |> Utils.verify_result()
  end

  def set_read_version(%Transaction{} = transaction, version) do
    Native.transaction_set_read_version(transaction.resource, version)
    |> Utils.verify_result()
  end

  def atomic_op(%Transaction{} = transaction, key, value, op) do
    Native.transaction_atomic_op(
      transaction.resource,
      Coder.encode_key(transaction.coder, key),
      value,
      op
    )
    |> Utils.verify_result()
  end

  def clear(%Transaction{} = transaction, key) do
    Native.transaction_clear(transaction.resource, Coder.encode_key(transaction.coder, key))
    |> Utils.verify_result()
  end

  def clear_range(%Transaction{} = transaction, key_range) do
    begin_key = Coder.encode_range(transaction.coder, key_range.begin.key, key_range.begin.prefix)
    end_key = Coder.encode_range(transaction.coder, key_range.end.key, key_range.end.prefix)

    Native.transaction_clear_range(transaction.resource, begin_key, end_key)
    |> Utils.verify_result()
  end

  def commit(%Transaction{} = transaction) do
    commit_q(transaction)
    |> Future.await()
  end

  def commit_q(%Transaction{} = transaction) do
    Native.transaction_commit(transaction.resource)
    |> Future.create()
  end

  def cancel(%Transaction{} = transaction) do
    Native.transaction_cancel(transaction.resource)
    |> Utils.verify_result()
  end

  def on_error(%Transaction{} = transaction, code) when is_integer(code) do
    on_error_q(transaction, code)
    |> Future.await()
  end

  def on_error_q(%Transaction{} = transaction, code) when is_integer(code) do
    Native.transaction_on_error(transaction.resource, code)
    |> Future.create()
  end

  def add_conflict_range(%Transaction{} = transaction, key_range, type) do
    begin_key = Coder.encode_range(transaction.coder, key_range.begin.key, key_range.begin.prefix)

    end_key = Coder.encode_range(transaction.coder, key_range.end.key, key_range.end.prefix)

    Native.transaction_add_conflict_range(transaction.resource, begin_key, end_key, type)
    |> Utils.verify_result()
  end
end
