defmodule FDB.Native do
  @moduledoc false

  @on_load {:init, 0}
  @compile {:autoload, false}
  @app Mix.Project.config()[:app]

  def init do
    path = :filename.join(:code.priv_dir(@app), 'fdb_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  def get_max_api_version, do: :erlang.nif_error(:nif_library_not_loaded)

  def select_api_version_impl(_runtime_version, _header_version),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def network_set_option(_option), do: :erlang.nif_error(:nif_library_not_loaded)
  def network_set_option(_option, _value), do: :erlang.nif_error(:nif_library_not_loaded)
  def setup_network, do: :erlang.nif_error(:nif_library_not_loaded)
  def run_network, do: :erlang.nif_error(:nif_library_not_loaded)
  def stop_network, do: :erlang.nif_error(:nif_library_not_loaded)
  def create_cluster(_file_path), do: :erlang.nif_error(:nif_library_not_loaded)
  def cluster_set_option(_cluster, _option), do: :erlang.nif_error(:nif_library_not_loaded)

  def cluster_set_option(_cluster, _option, _value),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def cluster_create_database(_cluster), do: :erlang.nif_error(:nif_library_not_loaded)
  def database_set_option(_database, _option), do: :erlang.nif_error(:nif_library_not_loaded)

  def database_set_option(_database, _option, _value),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def database_create_transaction(_database), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_set_option(_transaction, _option),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_set_option(_transaction, _option, _value),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get(_transaction, _key, _snapshot),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_read_version(_transaction), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_committed_version(_transaction),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_versionstamp(_transaction), do: :erlang.nif_error(:nif_library_not_loaded)
  def transaction_watch(_transaction, _key), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_key(_transaction, _key, _or_equal, _offset, _snapshot),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_addresses_for_key(_transaction, _key),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_get_range(
        _transaction,
        _begin_key,
        _begin_or_equal,
        _begin_offset,
        _end_key,
        _end_or_equal,
        _end_offset,
        _limit,
        _target_bytes,
        _mode,
        _iteration,
        _snapshot,
        _reverse
      ),
      do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_set(_transaction, _key, _value), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_set_read_version(_transaction, _version),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_add_conflict_range(_transaction, _begin_key, _end_key, _conflict_range_type),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_atomic_op(_transaction, _key, _param, _operation_type),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_clear(_transaction, _key), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_clear_range(_transaction, _begin_key, _end_key),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_commit(_transaction), do: :erlang.nif_error(:nif_library_not_loaded)
  def transaction_cancel(_transaction), do: :erlang.nif_error(:nif_library_not_loaded)

  def transaction_on_error(_transaction, _error_code),
    do: :erlang.nif_error(:nif_library_not_loaded)

  def get_error(_code), do: :erlang.nif_error(:nif_library_not_loaded)
  def get_error_predicate(_predicate_test, _code), do: :erlang.nif_error(:nif_library_not_loaded)
  def future_resolve(_future, _reference), do: :erlang.nif_error(:nif_library_not_loaded)
end
