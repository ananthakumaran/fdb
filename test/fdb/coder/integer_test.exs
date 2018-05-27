defmodule FDB.Coder.IntegerTest do
  alias FDB.Coder.Integer
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all numbers <- list_of(integer(-0xFFFFFFFFFFFFFFFF..0xFFFFFFFFFFFFFFFF)) do
      coder = Integer.new()
      assert_coder_order_symmetry(coder, numbers)
    end
  end

  test "examples" do
    coder = Integer.new()
    assert coder.module.encode(-5_551_212, nil) == <<0x11, 0xAB, "K", 0x93>>
    assert coder.module.encode(-1, nil) == <<0x13, 0xFE>>
  end
end
