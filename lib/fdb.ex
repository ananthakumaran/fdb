defmodule FDB do
  alias FDB.Network
  alias FDB.Native
  alias FDB.Utils

  @spec start(integer) :: :ok
  def start(version \\ 510) do
    select_api_version(version)
    :ok = Network.setup()
    :ok = Network.run()
  end

  @spec select_api_version(integer) :: :ok
  def select_api_version(version \\ 510) do
    Native.select_api_version_impl(version, 510)
    |> Utils.verify_result()
  end
end
