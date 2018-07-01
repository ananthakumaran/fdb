defmodule FDB.Cluster do
  @moduledoc """
  This module provides functions to create and configure cluster
  """
  alias FDB.Native
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Option

  defstruct resource: nil

  @type t :: %__MODULE__{resource: identifier}

  @doc """
  Creates a new Cluster. If the `cluster_file_path` is not set then
  [default cluster
  file](https://apple.github.io/foundationdb/administration.html#default-cluster-file)
  will be used.
  """
  @spec create(String.t() | nil) :: t
  def create(cluster_file_path \\ nil) do
    create_q(cluster_file_path)
    |> Future.await()
  end

  @doc """
  Async version of `create/1`
  """
  @spec create_q(String.t() | nil) :: Future.t()
  def create_q(file_path \\ nil) do
    Native.create_cluster(file_path)
    |> Future.create()
    |> Future.map(&%__MODULE__{resource: &1})
  end

  @doc false
  @spec set_option(t, Option.key()) :: :ok
  def set_option(%__MODULE__{} = cluster, option) do
    Native.cluster_set_option(cluster.resource, option)
    |> Utils.verify_ok()
  end

  @doc false
  @spec set_option(t, Option.key(), Option.value()) :: :ok
  def set_option(%__MODULE__{} = cluster, option, value) do
    Native.cluster_set_option(cluster.resource, option, value)
    |> Utils.verify_ok()
  end
end
