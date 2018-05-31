defmodule FDB.Coder.ArbitraryIntegerTest do
  alias FDB.Coder.ArbitraryInteger
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all numbers <- list_of(integer()) do
      coder = ArbitraryInteger.new()
      assert_coder_order_symmetry(coder, numbers)
    end
  end
end
