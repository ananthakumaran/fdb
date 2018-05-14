defmodule FDB.Raw do
  @on_load :init

  def init do
    :ok = :erlang.load_nif('./priv/fdb_nif', 0)
  end

  def get_max_api_version, do: exit(:nif_library_not_loaded)
  def select_api_version_impl(runtime_version, header_version), do: exit(:nif_library_not_loaded)
  def setup_network, do: exit(:nif_library_not_loaded)
  def run_network, do: exit(:nif_library_not_loaded)
  def stop_network, do: exit(:nif_library_not_loaded)
  def create_cluster, do: exit(:nif_library_not_loaded)
  def get_error(code), do: exit(:nif_library_not_loaded)
  def future_resolve(future), do: exit(:nif_library_not_loaded)
end
