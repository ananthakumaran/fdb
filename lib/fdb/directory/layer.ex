defmodule FDB.Directory.Layer do
  alias FDB.Coder.{
    Subspace,
    Identity,
    ByteString,
    DirectoryVersion,
    Integer,
    UnicodeString,
    Tuple,
    LittleEndianInteger
  }

  alias FDB.Transaction
  alias FDB.KeySelectorRange
  alias FDB.Directory.HighContentionAllocator
  alias FDB.Directory.Node
  alias FDB.Directory
  alias FDB.KeySelector
  alias FDB.KeyRange
  alias FDB.Utils

  defstruct [
    :node_subspace,
    :content_subspace,
    :allow_manual_prefixes,
    :root_node,
    :node,
    :node_name_coder,
    :version_coder,
    :prefix_coder,
    :hca_coder,
    :content_coder,
    :path,
    :layer
  ]

  @directory_version {1, 0, 0}
  @subdirs 0

  def new(options \\ %{}) do
    node_subspace = Map.get(options, :node_subspace, Subspace.new(<<0xFE>>))

    node_name_coder =
      Transaction.Coder.new(
        Subspace.concat(
          node_subspace,
          Subspace.new(
            "",
            Tuple.new({ByteString.new(), Integer.new(), UnicodeString.new()}),
            Identity.new()
          )
        ),
        Identity.new()
      )

    prefix_coder =
      Transaction.Coder.new(
        Subspace.concat(
          node_subspace,
          Subspace.new(
            "",
            Tuple.new({ByteString.new(), Identity.new()}),
            Identity.new()
          )
        ),
        Identity.new()
      )

    root_node =
      Node.new(
        node_subspace,
        node_subspace.opts.prefix,
        [],
        []
      )

    hca_coder =
      Transaction.Coder.new(
        Subspace.concat(
          node_subspace,
          Subspace.new(root_node.prefix, Identity.new(), ByteString.new())
        )
        |> Subspace.concat(
          Subspace.new("hca", Tuple.new({Integer.new(), Integer.new()}), ByteString.new())
        ),
        LittleEndianInteger.new(64)
      )

    version_coder =
      Transaction.Coder.new(
        Subspace.concat(
          node_subspace,
          Subspace.new("", Tuple.new({ByteString.new(), ByteString.new()}))
        ),
        DirectoryVersion.new()
      )

    content_subspace = Map.get(options, :content_subspace, Subspace.new(<<>>))

    content_coder =
      Transaction.Coder.new(
        Subspace.concat(
          content_subspace,
          Subspace.new(
            "",
            Identity.new(),
            Identity.new()
          )
        ),
        Identity.new()
      )

    %__MODULE__{
      node_subspace: node_subspace,
      content_subspace: content_subspace,
      allow_manual_prefixes: Map.get(options, :allow_manual_prefixes, false),
      root_node: root_node,
      node_name_coder: node_name_coder,
      version_coder: version_coder,
      prefix_coder: prefix_coder,
      hca_coder: hca_coder,
      content_coder: content_coder,
      node: root_node,
      path: [],
      layer: ""
    }
  end

  def create_or_open_internal(directory, tr, path, allow_create, allow_open, options \\ %{}) do
    defaults = %{layer: "", prefix: nil}
    options = Map.merge(defaults, options)

    if options[:prefix] && allow_open && allow_create do
      raise ArgumentError, "Cannot specify a prefix when calling create_or_open."
    end

    if options[:prefix] && !directory.allow_manual_prefixes do
      if directory.path.length == 0 do
        raise ArgumentError, "Cannot specify a prefix unless manual prefixes are enabled."
      else
        raise ArgumentError, "Cannot specify a prefix in a partition."
      end
    end

    check_version(directory, tr, false)
    path = to_unicode_path(path)

    if length(path) == 0 do
      raise ArgumentError, "The root directory cannot be opened."
    end

    existing_node = Node.prefetch_metadata(find(directory, tr, path), tr)

    if Node.exists?(existing_node) do
      if Node.is_in_partition?(existing_node) do
        subpath = Node.get_partition_subpath(existing_node)

        Node.get_contents(existing_node, directory).directory
        |> create_or_open_internal(tr, subpath, allow_create, allow_open, options)
      else
        if !allow_open do
          raise ArgumentError, "The directory already exists."
        end

        open_directory(directory, path, options, existing_node)
      end
    else
      if !allow_create do
        raise ArgumentError, "The directory does not exist."
      end

      create_directory(directory, tr, path, options)
    end
  end

  def open_directory(directory, _path, options, existing_node) do
    if options[:layer] && options[:layer] != "" && options[:layer] != existing_node.layer do
      raise ArgumentError, "The directory was created with an incompatible layer."
    end

    Node.get_contents(existing_node, directory)
  end

  def create_directory(directory, tr, path, options) do
    check_version(directory, tr, true)

    prefix = options[:prefix]

    prefix =
      cond do
        !prefix ->
          prefix =
            directory.content_subspace.opts.prefix <>
              HighContentionAllocator.allocate(directory, tr)

          unless Transaction.get_range(tr, KeySelectorRange.starts_with(prefix), %{limit: 1})
                 |> Enum.empty?() do
            raise ArgumentError,
                  "The database has keys stored at the prefix chosen by the automatic prefix allocator: #{
                    inspect(prefix)
                  }."
          end

          unless prefix_free?(directory, tr, prefix) do
            raise ArgumentError,
                  "The directory layer has manually allocated prefixes that conflict with the automatic prefix allocator."
          end

          prefix

        prefix ->
          if !prefix_free?(directory, tr, prefix) do
            raise ArgumentError, "The given prefix is already in use."
          end

          prefix
      end

    parent_node =
      if length(Enum.drop(path, -1)) > 0 do
        parent = Directory.create_or_open(directory, tr, Enum.drop(path, -1))
        node_with_prefix(directory, parent.prefix)
      else
        directory.root_node
      end

    if !parent_node do
      raise "The parent directory does not exist."
    end

    node = node_with_prefix(directory, prefix)

    Transaction.set(tr, {parent_node.prefix, @subdirs, List.last(path)}, prefix, %{
      coder: directory.node_name_coder
    })

    Transaction.set(tr, {}, options[:layer], %{coder: node.layer_coder})

    contents_of_node(directory, node, path, options[:layer])
  end

  def remove_internal(directory, tr, path, fail_on_nonexistent) do
    check_version(directory, tr, true)

    path = to_unicode_path(path)

    if Enum.empty?(path) do
      raise ArgumentError, "The root directory cannot be removed."
    end

    node = Node.prefetch_metadata(find(directory, tr, path), tr)

    cond do
      !Node.exists?(node) ->
        if fail_on_nonexistent do
          raise ArgumentError, "The directory does not exist."
        else
          false
        end

      Node.is_in_partition?(node) ->
        d = Node.get_contents(node, directory).directory

        remove_internal(
          d,
          tr,
          Node.get_partition_subpath(node),
          fail_on_nonexistent
        )

      true ->
        remove_recursive(directory, tr, node)
        remove_from_parent(directory, tr, path)
        true
    end
  end

  def find(directory, tr, path) do
    node = Node.new(directory.root_node, directory.root_node.prefix, [], path)

    do_find(directory, tr, node, [], path)
  end

  defp do_find(_directory, _tr, node, _, []), do: node

  defp do_find(directory, tr, node, current, [name | rest] = target) do
    prefix = Transaction.get(tr, {name}, %{coder: node.subdir_coder})

    node =
      Node.new(node_with_prefix(directory, prefix), prefix, current ++ [name], current ++ target)

    if Node.exists?(node) do
      {node, layer} = Node.layer(node, tr)

      if layer != "partition" do
        do_find(directory, tr, node, current ++ [name], rest)
      else
        node
      end
    else
      node
    end
  end

  def contents_of_node(directory, node, path, layer) do
    if layer == "partition" do
      FDB.Directory.Partition.new(directory.path ++ path, node.prefix, directory)
    else
      FDB.Directory.Subspace.new(directory.path ++ path, node.prefix, directory, layer)
    end
  end

  def node_with_prefix(directory, prefix) do
    if prefix do
      Node.new(
        directory.node_subspace,
        prefix,
        [],
        []
      )
    end
  end

  def subdir_names_and_nodes(directory, tr, node) do
    Transaction.get_range(tr, KeySelectorRange.starts_with({}), %{
      coder: node.subdir_coder
    })
    |> Enum.map(fn {{name}, subdirectory_prefix} ->
      {name, node_with_prefix(directory, subdirectory_prefix)}
    end)
  end

  def remove_from_parent(directory, tr, path) do
    parent = find(directory, tr, Enum.drop(path, -1))

    :ok =
      Transaction.clear(tr, {parent.prefix, @subdirs, List.last(path)}, %{
        coder: directory.node_name_coder
      })
  end

  def remove_recursive(directory, tr, node) do
    Enum.each(subdir_names_and_nodes(directory, tr, node), fn {_name, subnode} ->
      remove_recursive(directory, tr, subnode)
    end)

    :ok =
      Transaction.clear_range(tr, KeyRange.starts_with({node.prefix}), %{
        coder: directory.node_name_coder
      })

    :ok =
      Transaction.clear_range(tr, KeyRange.starts_with(node.prefix), %{
        coder: directory.content_coder
      })
  end

  def prefix_free?(directory, tr, prefix) do
    root_prefix = directory.root_node.prefix

    prefix && byte_size(prefix) > 0 && !Utils.starts_with?(root_prefix, prefix) &&
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

  def to_unicode_path(path) when is_list(path), do: path
  def to_unicode_path(path), do: [path]

  def check_version(directory, tr, write_access) do
    coder = directory.version_coder
    version = Transaction.get(tr, {directory.root_node.prefix, "version"}, %{coder: coder})

    case version do
      nil when write_access ->
        :ok =
          Transaction.set(
            tr,
            {directory.root_node.prefix, "version"},
            @directory_version,
            %{
              coder: coder
            }
          )

      nil when not write_access ->
        :ok

      {major, _, _} when major != 1 ->
        raise ArgumentError,
              "Cannot load directory with version #{inspect(version)} using directory layer #{
                inspect(@directory_version)
              }"

      {_, minor, _} when minor != 0 and write_access ->
        raise ArgumentError,
              "Directory with version #{inspect(version)} is read-only when opened using directory layer #{
                inspect(@directory_version)
              }"

      _ ->
        :ok
    end
  end
end

defimpl FDB.Directory, for: FDB.Directory.Layer do
  alias FDB.Directory
  alias FDB.Directory.Node
  alias FDB.Directory.Layer

  def layer(directory) do
    directory.layer
  end

  def path(directory) do
    directory.path
  end

  def create_or_open(directory, tr, path, options \\ %{}) do
    Layer.create_or_open_internal(directory, tr, path, true, true, options)
  end

  def open(directory, tr, path, options \\ %{}) do
    Layer.create_or_open_internal(directory, tr, path, false, true, options)
  end

  def create(directory, tr, path, options \\ %{}) do
    Layer.create_or_open_internal(directory, tr, path, true, false, options)
  end

  def move_to(_directory, _tr, _new_absolute_path) do
    raise ArgumentError, "The root directory cannot be moved"
  end

  def move(directory, tr, old_path, new_path) do
    Layer.check_version(directory, tr, true)

    old_path = Layer.to_unicode_path(old_path)
    new_path = Layer.to_unicode_path(new_path)

    if old_path == Enum.take(new_path, length(old_path)) do
      raise ArgumentError,
            "The desination directory cannot be a subdirectory of the source directory."
    end

    old_node = Node.prefetch_metadata(Layer.find(directory, tr, old_path), tr)
    new_node = Node.prefetch_metadata(Layer.find(directory, tr, new_path), tr)

    unless Node.exists?(old_node) do
      raise ArgumentError, "The source directory does not exist."
    end

    if Node.is_in_partition?(old_node) || Node.is_in_partition?(new_node) do
      if !Node.is_in_partition?(old_node) || !Node.is_in_partition?(new_node) ||
           old_node.path != new_node.path do
        raise ArgumentError, "Cannot move between partitions"
      end

      Node.get_contents(new_node, directory)
      |> FDB.Directory.move(
        tr,
        Node.get_partition_subpath(old_node),
        Node.get_partition_subpath(new_node)
      )
    else
      if Node.exists?(new_node) do
        raise ArgumentError, "The destination directory already exists. Remove it first."
      end

      parent_node = Layer.find(directory, tr, Enum.drop(new_path, -1))

      if !Node.exists?(parent_node) do
        raise ArgumentError,
              "The parent directory of the destination directory does not exist. Create it first."
      end

      Node.subdir(parent_node, tr, List.last(new_path), old_node.prefix)
      Layer.remove_from_parent(directory, tr, old_path)

      Layer.contents_of_node(directory, old_node, new_path, old_node.layer)
    end
  end

  def remove(directory, tr, path \\ []) do
    Layer.remove_internal(directory, tr, path, true)
  end

  def remove_if_exists(directory, tr, path \\ []) do
    Layer.remove_internal(directory, tr, path, false)
  end

  def list(directory, tr, path \\ []) do
    Layer.check_version(directory, tr, false)

    path = Layer.to_unicode_path(path)
    node = Node.prefetch_metadata(Layer.find(directory, tr, path), tr)

    if !Node.exists?(node) do
      raise ArgumentError, "The directory does not exist."
    end

    if Node.is_in_partition?(node, nil, true) do
      Node.get_contents(node, directory)
      |> Directory.list(tr, Node.get_partition_subpath(node))
    else
      Enum.map(Layer.subdir_names_and_nodes(directory, tr, node), fn {name, _node} ->
        name
      end)
    end
  end

  def exists?(directory, tr, path \\ []) do
    Layer.check_version(directory, tr, false)

    path = Layer.to_unicode_path(path)
    node = Node.prefetch_metadata(Layer.find(directory, tr, path), tr)

    cond do
      !Node.exists?(node) ->
        false

      Node.is_in_partition?(node) ->
        Node.get_contents(node, directory)
        |> Directory.exists?(tr, Node.get_partition_subpath(node))

      true ->
        true
    end
  end
end
