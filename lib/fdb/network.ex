defmodule FDB.Network do
  alias FDB.Native
  alias FDB.Utils
  alias FDB.Option

  @spec setup() :: :ok
  def setup() do
    Native.setup_network()
    |> Utils.verify_ok()
  end

  @spec run() :: :ok
  def run() do
    Native.run_network()
    |> Utils.verify_ok()
  end

  @spec stop() :: :ok
  def stop do
    Native.stop_network()
    |> Utils.verify_ok()
  end

  @spec set_option(Option.key()) :: :ok
  def set_option(option) do
    Option.verify_network_option(option)

    Native.network_set_option(option)
    |> Utils.verify_ok()
  end

  @spec set_option(Option.key(), Option.value()) :: :ok
  def set_option(option, value) do
    Option.verify_network_option(option, value)

    Native.network_set_option(option, Option.normalize_value(value))
    |> Utils.verify_ok()
  end
end
