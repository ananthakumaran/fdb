defmodule FDB.Directory.Node do
  @subdirs 0
  @layer "layer"

  alias FDB.Transaction
  alias FDB.KeySelector
  alias FDB.KeySelectorRange
  alias FDB.Utils

  defstruct [:prefix, :path, layer: "", parent: nil]

  def name(node) do
    case node.path do
      [] -> ""
      path -> List.last(path)
    end
  end

  def root?(node) do
    node.path == [] && node.parent == nil
  end

  defp fetch(directory, node, tr) do
    layer =
      Transaction.get(tr, {node.prefix, @layer}, %{
        coder: directory.node_layer_coder
      })

    %{node | layer: layer}
  end

  def find(directory, tr, path) do
    node = directory.node

    Enum.reduce(path, node, fn
      _part, nil ->
        nil

      part, node ->
        subdirectory(directory, tr, node, part)
    end)
  end

  def create_subdirectory(directory, tr, %{name: name, prefix: prefix, layer: layer}) do
    parent = directory.node

    :ok =
      Transaction.set(tr, {parent.prefix, @subdirs, name}, prefix, %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.set(tr, {prefix, @layer}, layer, %{
        coder: directory.node_layer_coder
      })

    %__MODULE__{
      parent: parent,
      layer: layer,
      path: parent.path ++ [name],
      prefix: prefix
    }
  end

  def remove(directory, tr) do
    node = directory.node
    parent = node.parent

    :ok =
      Transaction.set(tr, {parent.prefix, @subdirs, name(node)}, node.prefix, %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.set(tr, {node.prefix, @layer}, node.layer, %{
        coder: directory.node_layer_coder
      })
  end

  def subdirectory(directory, tr, node, name) do
    case Transaction.get(tr, {node.prefix, @subdirs, name}, %{coder: directory.node_name_coder}) do
      nil ->
        nil

      prefix ->
        fetch(directory, %__MODULE__{prefix: prefix, path: node.path ++ [name], parent: node}, tr)
    end
  end

  def subdirectories(directory, tr, node) do
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
end
