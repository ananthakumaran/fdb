defmodule FDB.Coder.FloatTest do
  alias FDB.Coder.Float
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  property "encode / decode" do
    check all numbers64 <- list_of(float()) do
      coder32 = Float.new(32)
      coder64 = Float.new(64)

      # reduce to 32 bits
      numbers32 =
        Enum.map(numbers64, fn n ->
          <<n::32-float-big>> = <<n::32-float-big>>
          n
        end)

      assert_coder_order_symmetry(coder64, numbers64)
      assert_coder_order_symmetry(coder32, numbers32)
    end
  end

  test "examples" do
    coder = Float.new()
    assert coder.module.encode(-42, 32) == <<0x20, "=", 0xD7, 0xFF, 0xFF>>
  end

  test "order" do
    coder = %FDB.Coder{
      module: FDB.Coder.Nullable,
      opts: %FDB.Coder{module: FDB.Coder.Float, opts: 32}
    }

    values = [1.0, 3.0, 1.0, -3.0, 3.0, -0.0, 3.0, 0.0, 1.0, -1.0]
    assert_coder_order_symmetry(coder, values)
  end
end
