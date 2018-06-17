defmodule FDB.Network do
  alias FDB.Native
  alias FDB.Utils
  alias FDB.Option

  def start(version \\ 510) do
    Native.select_api_version_impl(version, 510)
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
    Option.verify_network_option(option)

    Native.network_set_option(option)
    |> Utils.verify_result()
  end

  def set_option(option, value) do
    Option.verify_network_option(option, value)

    Native.network_set_option(option, Option.normalize_value(value))
    |> Utils.verify_result()
  end
end
