defmodule FDB.Network do
  alias FDB.Native
  alias FDB.KeySelector
  alias FDB.Utils

  def start do
    Native.select_api_version_impl(510, 510)
    |> Utils.verify_result()

    Native.setup_network()
    |> Utils.verify_result()

    Native.run_network()
    |> Utils.verify_result()
  end

  def stop do
    Native.stop_network()
    |> Utils.verify_result()
  end

  def set_option(option) do
    Native.network_set_option(option)
    |> Utils.verify_result()
  end

  def set_option(option, value) do
    Native.network_set_option(option, value)
    |> Utils.verify_result()
  end
end
