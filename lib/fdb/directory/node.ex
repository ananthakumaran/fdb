defmodule FDB.Directory.Node do
  alias FDB.Coder.{Tuple, ByteString, Identity, Subspace, UnicodeString, Integer}
  alias FDB.Transaction

  defstruct [:subspace, :prefix, :layer_coder, :subdir_coder, :path, :target_path, layer: nil]

  def new(nil, prefix, path, target_path) do
    %__MODULE__{
      path: path,
      target_path: target_path,
      prefix: prefix
    }
  end

  def new(%__MODULE__{} = node, prefix, path, target_path) do
    new(node.subspace, prefix, path, target_path)
  end

  def new(subspace, prefix, path, target_path) do
    layer_coder =
      Transaction.Coder.new(
        Subspace.concat(
          subspace,
          Subspace.new(
            {prefix, "layer"},
            Tuple.new({}),
            Tuple.new({ByteString.new(), ByteString.new()})
          )
        ),
        Identity.new()
      )

    subdir_coder =
      Transaction.Coder.new(
        Subspace.concat(
          subspace,
          Subspace.new(
            {prefix, 0},
            Tuple.new({UnicodeString.new()}),
            Tuple.new({ByteString.new(), Integer.new()})
          )
        ),
        Identity.new()
      )

    %__MODULE__{
      subspace: subspace,
      prefix: prefix,
      path: path,
      target_path: target_path,
      layer: nil,
      layer_coder: layer_coder,
      subdir_coder: subdir_coder
    }
  end

  def exists?(node) do
    !!node.subspace
  end

  def prefetch_metadata(node, tr) do
    if exists?(node) do
      {node, _} = layer(node, tr)
      node
    else
      node
    end
  end

  def layer(node, tr \\ nil) do
    if tr do
      layer = Transaction.get(tr, {}, %{coder: node.layer_coder})
      {%{node | layer: layer}, layer}
    else
      if !node.layer do
        raise "Layer has not been read"
      end

      {node, node.layer}
    end
  end

  def is_in_partition?(node, _tr \\ nil, include_empty_subpath \\ false) do
    exists?(node) && node.layer == "partition" &&
      (include_empty_subpath || length(node.path) < length(node.target_path))
  end

  def get_partition_subpath(node, _tr \\ nil) do
    Enum.drop(node.target_path, length(node.path))
  end

  def get_contents(node, directory, tr \\ nil) do
    {_node, layer} = layer(node, tr)
    FDB.Directory.Layer.contents_of_node(directory, node, node.path, layer)
  end

  def subdir(node, tr, name, prefix) do
    Transaction.set(tr, {name}, prefix, %{coder: node.subdir_coder})
  end
end
