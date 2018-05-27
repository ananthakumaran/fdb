defmodule FDB.Coder.ByteStringTest do
  alias FDB.Coder.ByteString
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all binaries <- list_of(binary()) do
      coder = ByteString.new()
      assert_coder_order_symmetry(coder, binaries)
    end
  end
end
