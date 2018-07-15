defmodule FDB.Directory do
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

  defstruct [
    :node_subspace,
    :content_subspace,
    :allow_manual_prefixes,
    :root_node,
    :node,
    :database,
    :node_name_coder,
    :node_layer_coder,
    :version_coder,
    :prefix_coder,
    :hca_coder
  ]

  @directory_version {1, 0, 0}

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

    node_layer_coder =
      Transaction.Coder.new(
        Subspace.concat(
          node_subspace,
          Subspace.new(
            "",
            Tuple.new({ByteString.new(), ByteString.new()}),
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

    root_node = %Node{prefix: node_subspace.opts.prefix, path: []}

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

    %__MODULE__{
      node_subspace: node_subspace,
      content_subspace: Map.get(options, :content_subspace, Subspace.new(<<>>)),
      allow_manual_prefixes: Map.get(options, :allow_manual_prefixes, false),
      root_node: root_node,
      node_name_coder: node_name_coder,
      version_coder: version_coder,
      prefix_coder: prefix_coder,
      hca_coder: hca_coder,
      node_layer_coder: node_layer_coder,
      node: root_node
    }
  end

  def list(directory, tr, path \\ []) do
    check_version(directory, tr, false)

    case Node.find(directory, tr, path) do
      nil ->
        raise ArgumentError, "The directory does not exist"

      node ->
        Node.subdirectories(directory, tr, node)
        |> Enum.map(&Node.name/1)
    end
  end

  def open(directory, tr, path, options \\ %{}) do
    check_version(directory, tr, false)

    case Node.find(directory, tr, path) do
      nil ->
        raise ArgumentError, "The directory does not exist"

      node ->
        layer = Map.get(options, :layer)

        if layer && node.layer != layer do
          raise ArgumentError, "The directory was created with an incompatible layer."
        end

        %{directory | node: node}
    end
  end

  def exists?(directory, tr, path \\ []) do
    check_version(directory, tr, false)

    case refetch_node(directory, tr, path) do
      nil -> false
      _node -> true
    end
  end

  def create(directory, tr, path, options \\ %{}) do
    check_version(directory, tr, false)

    case Node.find(directory, tr, path) do
      node when not is_nil(node) ->
        raise ArgumentError, "The directory already exists"

      nil ->
        do_create(directory, tr, path, options)
    end
  end

  def create_or_open(directory, tr, path, options \\ %{}) do
    check_version(directory, tr, false)

    case Node.find(directory, tr, path) do
      node when not is_nil(node) ->
        %{directory | node: node}

      nil ->
        do_create(directory, tr, path, options)
    end
  end

  def move_to(directory, tr, new_path) do
    check_version(directory, tr, true)
    root_directory = %{directory | node: directory.root_node}
    from = refetch_node(directory, tr)

    cond do
      is_nil(from) -> raise ArgumentError, "The source directory does not exist."
      Node.root?(from) -> raise ArgumentError, "The root directory cannot be moved."
      true -> :ok
    end

    old_path = from.path
    new_parent_path = Enum.drop(new_path, -1)

    if old_path == new_parent_path do
      raise ArgumentError,
            "The desination directory cannot be a subdirectory of the source directory."
    end

    to = Node.find(root_directory, tr, new_path)

    if to do
      raise ArgumentError, "The destination directory already exists. Remove it first."
    end

    to_parent = Node.find(root_directory, tr, new_parent_path)

    if !to_parent do
      raise ArgumentError,
            "The parent directory of the destination directory does not exist. Create it first."
    end

    :ok = Node.remove(directory, tr)

    to =
      Node.create_subdirectory(%{directory | node: to_parent}, tr, %{
        name: List.last(new_path),
        prefix: from.prefix,
        layer: from.layer
      })

    %{directory | node: to}
  end

  def remove(directory, tr, path \\ []) do
    check_version(directory, tr, true)
    node = refetch_node(directory, tr, path)

    cond do
      is_nil(node) ->
        raise ArgumentError, "The directory does not exist."

      Node.root?(node) ->
        raise ArgumentError, "The root directory cannot be removed."

      true ->
        :ok = Node.remove_all(directory, tr)
    end
  end

  def remove_if_exists(directory, tr, path \\ []) do
    check_version(directory, tr, true)
    node = refetch_node(directory, tr, path)

    cond do
      is_nil(node) ->
        false

      Node.root?(node) ->
        raise ArgumentError, "The root directory cannot be removed."

      true ->
        :ok = Node.remove_all(directory, tr)
        true
    end
  end

  defp refetch_node(directory, tr, path \\ []) do
    root_directory = %{directory | node: directory.root_node}
    Node.find(root_directory, tr, directory.node.path ++ path)
  end

  defp do_create(directory, tr, path, options) do
    check_version(directory, tr, true)
    prefix = Map.get(options, :prefix)
    layer = Map.get(options, :layer, "")

    prefix =
      cond do
        prefix ->
          if !prefix_free?(directory, tr, prefix) do
            raise ArgumentError, "The given prefix #{inspect(prefix)}is already in use."
          else
            prefix
          end

        true ->
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
      end

    parent_node = Node.find(directory, tr, Enum.drop(path, -1))

    unless parent_node do
      raise ArgumentError, "The parent directory does not exist."
    end

    node =
      Node.create_subdirectory(%{directory | node: parent_node}, tr, %{
        prefix: prefix,
        name: List.last(path),
        layer: layer
      })

    %{directory | node: node}
  end

  def prefix_free?(directory, tr, prefix) do
    prefix && byte_size(prefix) > 0 && Node.prefix_free?(directory, tr, prefix)
  end

  defp check_version(directory, tr, write_access) do
    coder = directory.version_coder
    version = Transaction.get(tr, {directory.root_node.prefix, "version"}, %{coder: coder})

    case version do
      nil when write_access ->
        :ok =
          Transaction.set(tr, {directory.root_node.prefix, "version"}, @directory_version, %{
            coder: coder
          })

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
