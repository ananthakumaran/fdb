defmodule FDB.Directory.Node do
  @subdirs 0
  @layer "layer"

  alias FDB.Transaction
  alias FDB.KeySelector
  alias FDB.KeySelectorRange
  alias FDB.KeyRange
  alias FDB.Utils
  alias FDB.Directory

  defstruct [:prefix, :path, layer: "", parent: nil]

  def name(directory) do
    case directory.node.path do
      [] -> ""
      path -> List.last(path)
    end
  end

  def full_path(directory) do
    if directory.parent_directory do
      full_path(directory.parent_directory) ++ directory.node.path
    else
      directory.node.path
    end
  end

  def root?(directory, path \\ [], follow_partition \\ true) do
    directory =
      if follow_partition do
        follow_partition(directory)
      else
        directory
      end

    node = directory.node
    path = node.path ++ path
    path == [] && node.parent == nil
  end

  def find(directory, tr, path) do
    root_directory = %{directory | node: directory.root_node}
    path = directory.node.path ++ path

    Enum.reduce(path, root_directory, fn
      _part, nil ->
        nil

      part, directory ->
        subdirectory(directory, tr, part)
    end)
  end

  def create_subdirectory(directory, tr, %{name: name, prefix: prefix, layer: layer}) do
    directory = follow_partition(directory)
    parent = directory.node

    :ok =
      Transaction.set(tr, {parent.prefix, @subdirs, name}, prefix, %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.set(tr, {prefix, @layer}, layer, %{
        coder: directory.node_layer_coder
      })

    node = %__MODULE__{
      parent: parent,
      layer: layer,
      path: parent.path ++ [name],
      prefix: prefix
    }

    %{directory | node: node}
  end

  def remove(directory, tr) do
    node = directory.node
    parent = node.parent

    :ok =
      Transaction.clear(tr, {parent.prefix, @subdirs, name(directory)}, %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.clear(tr, {node.prefix, @layer}, %{
        coder: directory.node_layer_coder
      })
  end

  def remove_all(directory, tr) do
    :ok = remove_subdirectories_recursively(directory, tr)
    remove(directory, tr)
  end

  defp remove_subdirectories_recursively(directory, tr) do
    subdirectories(directory, tr)
    |> Enum.each(&remove_subdirectories_recursively(&1, tr))

    node = directory.node

    :ok =
      Transaction.clear_range(tr, KeyRange.starts_with({node.prefix}), %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.clear_range(tr, KeyRange.starts_with(node.prefix), %{
        coder: directory.content_coder
      })
  end

  def subdirectory(directory, tr, name) do
    directory = follow_partition(directory)
    node = directory.node

    case Transaction.get(tr, {node.prefix, @subdirs, name}, %{coder: directory.node_name_coder}) do
      nil ->
        nil

      prefix ->
        fetch(directory, %__MODULE__{prefix: prefix, path: node.path ++ [name], parent: node}, tr)
    end
  end

  def subdirectories(directory, tr) do
    directory = follow_partition(directory)
    node = directory.node
    prefix = node.prefix

    Transaction.get_range(tr, KeySelectorRange.starts_with({prefix, @subdirs}), %{
      coder: directory.node_name_coder
    })
    |> Enum.map(fn {{^prefix, @subdirs, name}, subdirectory_prefix} ->
      fetch(
        directory,
        %__MODULE__{prefix: subdirectory_prefix, path: node.path ++ [name], parent: node},
        tr
      )
    end)
  end

  def follow_partition(directory) do
    if directory.node.layer == "partition" do
      Directory.partition_root(directory)
    else
      directory
    end
  end

  def prefix_free?(directory, tr, prefix) do
    root_node = directory.root_node

    !Utils.starts_with?(root_node.prefix, prefix) &&
      Transaction.get_range(
        tr,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal({}, %{prefix: :first}),
          KeySelector.first_greater_or_equal({prefix}, %{prefix: :first})
        ),
        %{
          coder: directory.prefix_coder,
          reverse: true,
          limit: 1
        }
      )
      |> Enum.filter(fn {{prev_prefix, _}, _} -> Utils.starts_with?(prefix, prev_prefix) end)
      |> Enum.empty?() &&
      Transaction.get_range(
        tr,
        KeySelectorRange.starts_with({prefix}),
        %{coder: directory.prefix_coder}
      )
      |> Enum.empty?()
  end

  defp fetch(directory, node, tr) do
    layer =
      Transaction.get(tr, {node.prefix, @layer}, %{
        coder: directory.node_layer_coder
      }) || ""

    %{directory | node: %{node | layer: layer}}
  end
end
