defmodule FDB.Coder.SubspaceTest do
  alias FDB.Coder.Subspace
  alias FDB.Coder.ByteString
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all binaries <- list_of(binary()),
              prefix <- binary() do
      coder = Subspace.new(prefix, ByteString.new())
      assert_coder_order_symmetry(coder, binaries)
    end
  end
end
