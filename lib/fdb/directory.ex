defmodule FDB.Directory do
  @moduledoc """
  Directory is one of the ways to [manage
  namespaces](https://apple.github.io/foundationdb/developer-guide.html#directories).

      root = FDB.Directory.new()
      dir = FDB.Database.transact(db, fn tr ->
        FDB.Directory.create_or_open(root, tr, ["users", "inactive"])
      end)
      inactive_subspace = FDB.Coder.Subspace.new(dir)
  """
  alias FDB.Directory.Protocol
  alias FDB.Directory.Layer
  alias FDB.Transaction

  @type t :: Protocol.t()
  @type path :: [String.t()]

  @doc """
  Creates root directory

  ## Options

  * node_subspace - (`t:FDB.Coder.t/0`) where the directory metadata should be stored. Defaults to `Subspace.new(<<0xFE>>)`
  * content_subspace - (`t:FDB.Coder.t/0`) where contents are stored. Defaults to `Subspace.new("")`
  * allow_manual_prefixes - (boolean) whether manual prefixes should be allowed for directories. Defaults to `false`
  """
  @spec new(map) :: t
  defdelegate new(options \\ %{}), to: Layer

  @doc """
  Gets the directory layer
  """
  @spec layer(t) :: String.t()
  defdelegate layer(directory), to: Protocol

  @doc """
  Gets the directory path
  """
  @spec path(t) :: path
  defdelegate path(directory), to: Protocol

  @doc """
  Gets the directory prefix
  """
  @spec prefix(t) :: binary
  defdelegate prefix(directory), to: Protocol

  @doc """
  Opens the directory with the given `path`. If the directory does not
  exist, it is created (creating parent directories if necessary).

  ## Options

  layer - (binary) if the layer is specified and the directory is new,
  it is recorded as the layer; if layer is specified and the directory
  already exists, it is compared against the layer specified when the
  directory was created, and the method will raise an exception if
  they differ.
  """
  @spec create_or_open(t, Transaction.t(), path, map) :: t
  defdelegate create_or_open(directory, tr, path, options \\ %{}), to: Protocol

  @doc """
  Opens the directory with given `path`. The function will raise an
  exception if the directory does not exist.

  ## Options

  layer - (binary) if the layer is specified, it is compared against
  the layer specified when the directory was created, and the function
  will raise an exception if they differ.
  """
  @spec open(t, Transaction.t(), path, map) :: t
  defdelegate open(directory, tr, path, options \\ %{}), to: Protocol

  @doc """
  Creates a directory with given `path`. Parent directories are
  created if necessary. The method will raise an exception if the
  given directory already exists.

  ## Options

  layer - (binary) if the layer is specified, it is recorded with the
  directory and will be checked by future calls to open.

  prefix - (binary) if prefix is specified, the directory is created
  with the given prefix; otherwise a prefix is allocated
  automatically.
  """
  @spec create(t, Transaction.t(), path, map) :: t
  defdelegate create(directory, tr, path, options \\ %{}), to: Protocol

  @doc """
  Moves this directory to new_path, interpreting new_path
  absolutely. There is no effect on the prefix of the given directory
  or on clients that already have the directory open. The function
  will raise an exception if a directory already exists at new_path or
  the parent directory of new_path does not exist.

  Returns the directory at its new location.
  """
  @spec move_to(t, Transaction.t(), path) :: t
  defdelegate move_to(directory, tr, new_absolute_path), to: Protocol

  @doc """
  Moves the directory at old_path to new_path. There is no effect on
  the prefix of the given directory or on clients that already have
  the directory open. The function will raise an exception if a
  directory does not exist at old_path, a directory already exists at
  new_path, or the parent directory of new_path does not exist.

  Returns the directory at its new location.
  """
  @spec move(t, Transaction.t(), path, path) :: t
  defdelegate move(directory, tr, old_path, new_path), to: Protocol

  @doc """
  Removes the directory at path, its contents, and all
  subdirectories. The function will raise an exception if the
  directory does not exist.

  > Clients that have already opened the directory might still insert
    data into its contents after removal.
  """
  @spec remove(t, Transaction.t(), path) :: t
  defdelegate remove(directory, tr, path \\ []), to: Protocol

  @doc """
  Checks if the directory at path exists and, if so, removes the
  directory, its contents, and all subdirectories. Returns `true` if
  the directory existed and `false` otherwise.

  > Clients that have already opened the directory might still insert
    data into its contents after removal.
  """
  @spec remove_if_exists(t, Transaction.t(), path) :: t
  defdelegate remove_if_exists(directory, tr, path \\ []), to: Protocol

  @doc """
  Returns `true` if the directory at path exists and `false` otherwise.
  """
  @spec exists?(t, Transaction.t(), path) :: t
  defdelegate exists?(directory, tr, path \\ []), to: Protocol

  @doc """
  Returns an list of names of the immediate subdirectories of the
  directory at path. Each name represents the last component of a
  subdirectory’s path.
  """
  @spec list(t, Transaction.t(), path) :: t
  defdelegate list(directory, tr, path \\ []), to: Protocol

  @doc false
  @spec get_layer_for_path(t, path) :: t
  defdelegate get_layer_for_path(directory, path), to: Protocol
end
