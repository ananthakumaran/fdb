defmodule FDB.Cluster do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Cluster

  defstruct resource: nil

  def create(file_path \\ nil) do
    create_q(file_path)
    |> Future.await()
  end

  def create_q(file_path \\ nil) do
    Native.create_cluster(file_path)
    |> Future.create()
    |> Future.map(&%Cluster{resource: &1})
  end

  def set_option(%Cluster{} = cluster, option) do
    Native.cluster_set_option(cluster.resource, option)
    |> Utils.verify_result()
  end

  def set_option(%Cluster{} = cluster, option, value) do
    Native.cluster_set_option(cluster.resource, option, value)
    |> Utils.verify_result()
  end
end
