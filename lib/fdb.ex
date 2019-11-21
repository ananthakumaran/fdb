defmodule FDB do
  @moduledoc """
  This module provides functions to initialize the library. Note that
  the functions in this module should be called only once.
  """
  alias FDB.Network
  alias FDB.Native
  alias FDB.Utils

  @doc """
  Sets the [API
  version](https://apple.github.io/foundationdb/api-general.html#api-versions)
  and starts the network thread. One should use `FDB.Network` directly
  if any of the network options need to be customized.
  """
  @spec start(integer) :: :ok
  def start(version \\ 620) do
    :ok = select_api_version(version)
    :ok = Network.setup()
    :ok = Network.run()
  end

  @doc """
  Sets the [API
  version](https://apple.github.io/foundationdb/api-general.html#api-versions). The
  maximum supported value is `620`.
  """
  @spec select_api_version(integer) :: :ok
  def select_api_version(version \\ 620) do
    Native.select_api_version_impl(version, 620)
    |> Utils.verify_ok()
  end
end
