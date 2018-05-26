defmodule FDB.Cluster do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils

  def create do
    Native.create_cluster()
    |> Future.resolve()
  end

  def set_option(cluster, option) do
    Native.cluster_set_option(cluster, option)
    |> Utils.verify_result()
  end

  def set_option(cluster, option, value) do
    Native.cluster_set_option(cluster, option, value)
    |> Utils.verify_result()
  end
end
