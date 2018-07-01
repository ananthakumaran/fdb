defmodule FDB.Network do
  @moduledoc """
  FoundationDB C API uses event loop architecture. All the network io
  operations are handled by a singleton network thread. This module
  provides functions to configure, start and stop the network
  thread. The functions should be called in the order given below

      :ok = FDB.select_api_version()
      # zero or more calls to set network options
      :ok = FDB.Network.set_option(FDB.Option.network_option_trace_enable())
      :ok = FDB.Network.setup()
      :ok = FDB.Network.run()
  """
  alias FDB.Native
  alias FDB.Utils
  alias FDB.Option

  @doc """
  Should be called after `FDB.select_api_version/1` and zero or more
  calls to `FDB.Network.set_option/1` or
  `FDB.Network.set_option/2`. This function should be called only
  once.
  """
  @spec setup() :: :ok
  def setup() do
    Native.setup_network()
    |> Utils.verify_ok()
  end

  @doc """
  Should be called after `FDB.Network.setup/0`. This function should
  be called only once.
  """
  @spec run() :: :ok
  def run() do
    Native.run_network()
    |> Utils.verify_ok()
  end

  @doc """
  Stops the network thread. Once stopped the network thread cannot be
  restarted again.
  """
  @spec stop() :: :ok
  def stop do
    Native.stop_network()
    |> Utils.verify_ok()
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `network_option_` is allowed.
  """
  @spec set_option(Option.key()) :: :ok
  def set_option(option) do
    Option.verify_network_option(option)

    Native.network_set_option(option)
    |> Utils.verify_ok()
  end

  @doc """
  Refer `FDB.Option` for the list of options. Any option that starts with `network_option_` is allowed.
  """
  @spec set_option(Option.key(), Option.value()) :: :ok
  def set_option(option, value) do
    Option.verify_network_option(option, value)

    Native.network_set_option(option, Option.normalize_value(value))
    |> Utils.verify_ok()
  end
end
