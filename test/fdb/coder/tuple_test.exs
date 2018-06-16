defmodule FDB.Coder.NestedTupleAndTupleTest do
  use ExUnit.Case
  use ExUnitProperties
  import TestUtils
  alias FDB.Coder.NestedTuple
  alias FDB.Coder.Tuple
  alias FDB.Coder.Integer
  alias FDB.Coder.ByteString
  alias FDB.Coder.UnicodeString
  alias FDB.Coder.Nullable

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

  @length 10

  property "encode / decode" do
    check all tuples <-
                list_of(
                  one_of([
                    {constant(UnicodeString.new()), list_of(string(@ranges), length: @length)},
                    {constant(Nullable.new(ByteString.new())),
                     list_of(one_of([constant(nil), binary()]), length: @length)},
                    {constant(Integer.new()),
                     list_of(integer(-0xFFFFFFFFFFFFFFFF..0xFFFFFFFFFFFFFFFF), length: @length)},
                    {constant(ByteString.new()), list_of(binary(), length: @length)}
                  ])
                ) do
      coders = Enum.map(tuples, fn {coder, _} -> coder end) |> List.to_tuple()
      nested_tuple_coder = NestedTuple.new(coders)
      tuple_coder = Tuple.new(coders)

      values =
        Enum.map(tuples, fn {_, values} -> values end)
        |> Enum.zip()

      assert_coder_order_symmetry(nested_tuple_coder, values)
      assert_coder_order_symmetry(tuple_coder, values)
    end
  end

  test "example" do
    coder =
      NestedTuple.new({ByteString.new(), Nullable.new(ByteString.new()), NestedTuple.new({})})

    encoded = coder.module.encode({<<"foo", 0x00, "bar">>, nil, {}}, coder.opts)
    assert encoded == <<0x05, 0x01, "foo", 0x00, 0xFF, "bar", 0x00, 0x00, 0xFF, 0x05, 0x00, 0x00>>
  end
end
