defmodule FDB.Coder.UnicodeStringTest do
  alias FDB.Coder.UnicodeString
  import TestUtils

  use ExUnit.Case
  use ExUnitProperties

  @ranges [
    0x00..0xF7,
    0xF8..0x37D,
    0x37F..0x1FFF,
    0x200C..0x200D,
    0x203F..0x2040,
    0x2070..0x218F,
    0x2C00..0x2FEF,
    0x3001..0xD7FF,
    0xF900..0xFDCF,
    0xFDF0..0xFFFD,
    0x10000..0xEFFFF
  ]

  property "encode / decode" do
    check all binaries <- list_of(string(@ranges)) do
      coder = UnicodeString.new()
      assert_coder_order_symmetry(coder, binaries)
    end
  end
end
