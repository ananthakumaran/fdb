defmodule FDB.Directory.Subspace do
  @moduledoc false

  defstruct [:path, :prefix, :directory, :layer]

  def new(path, prefix, directory, layer \\ "") do
    %__MODULE__{
      path: path,
      prefix: prefix,
      directory: directory,
      layer: layer
    }
  end
end

defimpl FDB.Directory.Protocol, for: [FDB.Directory.Subspace, FDB.Directory.Partition] do
  alias FDB.Directory

  def path(subspace) do
    subspace.path
  end

  def layer(subspace) do
    subspace.layer
  end

  def prefix(subspace) do
    if subspace.layer == "partition" do
      raise ArgumentError, "The root directory cannot used as a subspace"
    else
      subspace.prefix
    end
  end

  def create_or_open(subspace, tr, name_or_path, options \\ %{}) do
    path = tuplify_path(name_or_path)
    Directory.create_or_open(subspace.directory, tr, partition_subpath(subspace, path), options)
  end

  def open(subspace, tr, name_or_path, options \\ %{}) do
    path = tuplify_path(name_or_path)
    Directory.open(subspace.directory, tr, partition_subpath(subspace, path), options)
  end

  def create(subspace, tr, name_or_path, options \\ %{}) do
    path = tuplify_path(name_or_path)
    Directory.create(subspace.directory, tr, partition_subpath(subspace, path), options)
  end

  def list(subspace, tr, name_or_path \\ []) do
    path = tuplify_path(name_or_path)
    Directory.list(subspace.directory, tr, partition_subpath(subspace, path))
  end

  def move(subspace, tr, old_name_or_path, new_name_or_path) do
    old_path = tuplify_path(old_name_or_path)
    new_path = tuplify_path(new_name_or_path)

    Directory.move(
      subspace.directory,
      tr,
      partition_subpath(subspace, old_path),
      partition_subpath(subspace, new_path)
    )
  end

  def move_to(subspace, tr, new_absolute_name_or_path) do
    directory_layer = Directory.get_layer_for_path(subspace, [])
    new_absolute_path = tuplify_path(new_absolute_name_or_path)
    partition_len = length(directory_layer.path)
    partition_path = Enum.take(new_absolute_path, partition_len)

    if partition_path != directory_layer.path do
      raise ArgumentError, "Cannot move between partitions."
    end

    Directory.move(
      directory_layer,
      tr,
      Enum.drop(subspace.path, partition_len),
      Enum.drop(new_absolute_path, partition_len)
    )
  end

  def remove(subspace, tr, name_or_path \\ []) do
    path = tuplify_path(name_or_path)
    directory_layer = Directory.get_layer_for_path(subspace, path)
    Directory.remove(directory_layer, tr, partition_subpath(subspace, path, directory_layer))
  end

  def remove_if_exists(subspace, tr, name_or_path \\ []) do
    path = tuplify_path(name_or_path)
    directory_layer = Directory.get_layer_for_path(subspace, path)

    Directory.remove_if_exists(
      directory_layer,
      tr,
      partition_subpath(subspace, path, directory_layer)
    )
  end

  def exists?(subspace, tr, name_or_path \\ []) do
    path = tuplify_path(name_or_path)
    directory_layer = Directory.get_layer_for_path(subspace, path)
    Directory.exists?(directory_layer, tr, partition_subpath(subspace, path, directory_layer))
  end

  def tuplify_path(path) when is_binary(path), do: [path]
  def tuplify_path(path), do: path

  def partition_subpath(subspace, path, directory_layer \\ nil) do
    directory_layer = directory_layer || subspace.directory
    Enum.drop(subspace.path, length(directory_layer.path)) ++ path
  end

  def get_layer_for_path(%FDB.Directory.Subspace{} = subspace, _path) do
    subspace.directory
  end

  def get_layer_for_path(partition, path) do
    if Enum.empty?(path) do
      partition.parent_directory
    else
      partition.directory
    end
  end
end
