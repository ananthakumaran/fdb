defmodule FDB do
  alias FDB.Native
  alias FDB.KeySelector

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

  def network_set_option(option) do
    Native.network_set_option(option)
    |> verify_result
  end

  def network_set_option(option, value) do
    Native.network_set_option(option, value)
    |> verify_result
  end

  def create_cluster do
    Native.create_cluster()
    |> resolve
  end

  def cluster_set_option(cluster, option) do
    Native.cluster_set_option(cluster, option)
    |> verify_result
  end

  def cluster_set_option(cluster, option, value) do
    Native.cluster_set_option(cluster, option, value)
    |> verify_result
  end

  def create_database(cluster) do
    Native.cluster_create_database(cluster)
    |> resolve
  end

  def database_set_option(database, option) do
    Native.database_set_option(database, option)
    |> verify_result
  end

  def database_set_option(database, option, value) do
    Native.database_set_option(database, option, value)
    |> verify_result
  end

  def create_transaction(database) do
    Native.database_create_transaction(database)
    |> verify_result
  end

  def transaction_set_option(transaction, option) do
    Native.transaction_set_option(transaction, option)
    |> verify_result
  end

  def transaction_set_option(transaction, option, value) do
    Native.transaction_set_option(transaction, option, value)
    |> verify_result
  end

  def get(transaction, key) do
    Native.transaction_get(transaction, key, 0)
    |> resolve
  end

  def get_range(transaction, begin_key_selector, end_key_selector, options \\ %{}) do
    {begin_key, begin_or_equal, begin_offset} = begin_key_selector
    {end_key, end_or_equal, end_offset} = end_key_selector

    Native.transaction_get_range(
      transaction,
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
    |> resolve
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
          t = create_transaction(database)

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
              key

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
    Native.transaction_get(transaction, key, 1)
    |> resolve
  end

  def get_read_version(transaction) do
    Native.transaction_get_read_version(transaction)
    |> resolve
  end

  def set(transaction, key, value) do
    Native.transaction_set(transaction, key, value)
    |> verify_result
  end

  def atomic_op(transaction, key, value, op) do
    Native.transaction_atomic_op(transaction, key, value, op)
    |> verify_result
  end

  def clear(transaction, key) do
    Native.transaction_clear(transaction, key)
    |> verify_result
  end

  def clear_range(transaction, begin_key, end_key) do
    Native.transaction_clear_range(transaction, begin_key, end_key)
    |> verify_result
  end

  def commit(transaction) do
    Native.transaction_commit(transaction)
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
  defp verify_result({0, result}), do: result
  defp verify_result(code) when is_integer(code), do: raise(FDB.Error, Native.get_error(code))

  defp verify_result({code, _}) when is_integer(code),
    do: raise(FDB.Error, Native.get_error(code))
end
