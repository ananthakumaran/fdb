defmodule FDB.Coder.SignedLittleEndianIntegerTest do
  alias FDB.Coder.SignedLittleEndianInteger
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all numbers <- list_of(integer()) do
      coder = SignedLittleEndianInteger.new()
      assert_coder_order_symmetry(coder, numbers, sorted: false)
    end
  end
end
