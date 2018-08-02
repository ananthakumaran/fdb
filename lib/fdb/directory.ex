defmodule FDB.Directory do
  alias FDB.Directory.Protocol
  alias FDB.Directory.Layer
  alias FDB.Transaction

  @type t :: Protocol.t()
  @type path :: [String.t()]

  @spec new(map) :: t
  defdelegate new(options \\ %{}), to: Layer

  @spec layer(t) :: String.t()
  defdelegate layer(directory), to: Protocol

  @spec path(t) :: path
  defdelegate path(directory), to: Protocol

  @spec prefix(t) :: binary
  defdelegate prefix(directory), to: Protocol

  @spec create_or_open(t, Transaction.t(), path, map) :: t
  defdelegate create_or_open(directory, tr, path, options \\ %{}), to: Protocol

  @spec open(t, Transaction.t(), path, map) :: t
  defdelegate open(directory, tr, path, options \\ %{}), to: Protocol

  @spec create(t, Transaction.t(), path, map) :: t
  defdelegate create(directory, tr, path, options \\ %{}), to: Protocol

  @spec move_to(t, Transaction.t(), path) :: t
  defdelegate move_to(directory, tr, new_absolute_path), to: Protocol

  @spec move(t, Transaction.t(), path, path) :: t
  defdelegate move(directory, tr, old_path, new_path), to: Protocol

  @spec remove(t, Transaction.t(), path) :: t
  defdelegate remove(directory, tr, path \\ []), to: Protocol

  @spec remove_if_exists(t, Transaction.t(), path) :: t
  defdelegate remove_if_exists(directory, tr, path \\ []), to: Protocol

  @spec exists?(t, Transaction.t(), path) :: t
  defdelegate exists?(directory, tr, path \\ []), to: Protocol

  @spec list(t, Transaction.t(), path) :: t
  defdelegate list(directory, tr, path \\ []), to: Protocol

  @doc false
  @spec get_layer_for_path(t, path) :: t
  defdelegate get_layer_for_path(directory, path), to: Protocol
end
