defmodule FDB.Raw do
  @on_load :init

  def init do
    :ok = :erlang.load_nif('./priv/fdb_nif', 0)
  end

  def get_max_api_version() do
    exit(:nif_library_not_loaded)
  end
end
