defmodule FDB.Cluster do
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Option

  defstruct resource: nil

  @type t :: %__MODULE__{resource: identifier}

  @spec create(String.t() | nil) :: t
  def create(file_path \\ nil) do
    create_q(file_path)
    |> Future.await()
  end

  @spec create_q(String.t() | nil) :: Future.t()
  def create_q(file_path \\ nil) do
    Native.create_cluster(file_path)
    |> Future.create()
    |> Future.map(&%__MODULE__{resource: &1})
  end

  @spec set_option(t, Option.key()) :: :ok
  def set_option(%__MODULE__{} = cluster, option) do
    Native.cluster_set_option(cluster.resource, option)
    |> Utils.verify_ok()
  end

  @spec set_option(t, Option.key(), Option.value()) :: :ok
  def set_option(%__MODULE__{} = cluster, option, value) do
    Native.cluster_set_option(cluster.resource, option, value)
    |> Utils.verify_ok()
  end
end
