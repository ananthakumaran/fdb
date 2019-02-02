defmodule FDB.Coder.LittleEndianIntegerTest do
  alias FDB.Coder.LittleEndianInteger
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all numbers <- list_of(positive_integer()) do
      coder = LittleEndianInteger.new()
      assert_coder_order_symmetry(coder, numbers)
    end
  end
end
