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

  def setup_network, do: exit(:nif_library_not_loaded)
  def run_network, do: exit(:nif_library_not_loaded)
  def stop_network, do: exit(:nif_library_not_loaded)
  def create_cluster, do: exit(:nif_library_not_loaded)
  def cluster_create_database(_cluster), do: exit(:nif_library_not_loaded)
  def database_create_transaction(_database), do: exit(:nif_library_not_loaded)
  def transaction_get(_transaction, _key), do: exit(:nif_library_not_loaded)
  def get_error(_code), do: exit(:nif_library_not_loaded)
  def future_resolve(_future, _reference), do: exit(:nif_library_not_loaded)
end
