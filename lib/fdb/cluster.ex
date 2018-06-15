defmodule FDB.Cluster do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils

  def create(file_path \\ nil) do
    create_q(file_path)
    |> Future.resolve()
  end

  def create_q(file_path \\ nil) do
    Native.create_cluster(file_path)
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
