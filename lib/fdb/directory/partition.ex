defmodule FDB.Directory.Partition do
  @moduledoc false

  alias FDB.Directory.Layer
  alias FDB.Coder.{Subspace}

  defstruct [:path, :prefix, :parent_directory, :directory, :layer]

  def new(path, prefix, parent_directory) do
    %__MODULE__{
      path: path,
      prefix: prefix,
      layer: "partition",
      parent_directory: parent_directory,
      directory: %{
        Layer.new(%{
          node_subspace: Subspace.new(prefix <> <<0xFE>>),
          content_subspace: Subspace.new(prefix)
        })
        | path: path
      }
    }
  end
end
