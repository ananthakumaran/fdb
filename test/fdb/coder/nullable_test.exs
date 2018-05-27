defmodule FDB.Coder.NullableTest do
  alias FDB.Coder.Nullable
  alias FDB.Coder.ByteString
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all binaries <- list_of(one_of([constant(nil), binary()])) do
      coder = Nullable.new(ByteString.new())
      assert_coder_order_symmetry(coder, binaries)
    end
  end
end
