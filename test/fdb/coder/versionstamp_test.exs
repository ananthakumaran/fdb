defmodule FDB.Coder.VersionstampTest do
  import TestUtils
  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all versions <- list_of(map(binary(length: 12), &FDB.Versionstamp.new(&1))) do
      coder = FDB.Coder.Versionstamp.new()
      assert_coder_order_symmetry(coder, versions)
    end
  end
end
