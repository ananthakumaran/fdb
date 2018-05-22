defmodule FDB.Native do
  @moduledoc false

  @on_load {:init, 0}
  @compile {:autoload, false}
  @app Mix.Project.config()[:app]

  def init do
    path = :filename.join(:code.priv_dir(@app), 'fdb_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  def get_max_api_version, do: exit(:nif_library_not_loaded)

  def select_api_version_impl(_runtime_version, _header_version),
    do: exit(:nif_library_not_loaded)

  def network_set_option(_option), do: exit(:nif_library_not_loaded)
  def network_set_option(_option, _value), do: exit(:nif_library_not_loaded)
  def setup_network, do: exit(:nif_library_not_loaded)
  def run_network, do: exit(:nif_library_not_loaded)
  def stop_network, do: exit(:nif_library_not_loaded)
  def create_cluster, do: exit(:nif_library_not_loaded)
  def cluster_set_option(_cluster, _option), do: exit(:nif_library_not_loaded)
  def cluster_set_option(_cluster, _option, _value), do: exit(:nif_library_not_loaded)
  def cluster_create_database(_cluster), do: exit(:nif_library_not_loaded)
  def database_set_option(_database, _option), do: exit(:nif_library_not_loaded)
  def database_set_option(_database, _option, _value), do: exit(:nif_library_not_loaded)
  def database_create_transaction(_database), do: exit(:nif_library_not_loaded)
  def transaction_set_option(_transaction, _option), do: exit(:nif_library_not_loaded)
  def transaction_set_option(_transaction, _option, _value), do: exit(:nif_library_not_loaded)
  def transaction_get(_transaction, _key, _snapshot), do: exit(:nif_library_not_loaded)
  def transaction_get_read_version(_transaction), do: exit(:nif_library_not_loaded)

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
      do: exit(:nif_library_not_loaded)

  def transaction_set(_transaction, _key, _value), do: exit(:nif_library_not_loaded)

  def transaction_atomic_op(_transaction, _key, _param, _operation_type),
    do: exit(:nif_library_not_loaded)

  def transaction_clear(_transaction, _key), do: exit(:nif_library_not_loaded)

  def transaction_clear_range(_transaction, _begin_key, _end_key),
    do: exit(:nif_library_not_loaded)

  def transaction_commit(_transaction), do: exit(:nif_library_not_loaded)
  def get_error(_code), do: exit(:nif_library_not_loaded)
  def future_resolve(_future, _reference), do: exit(:nif_library_not_loaded)
end
