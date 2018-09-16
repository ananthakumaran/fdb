defmodule FDB.CoderTest do
  use ExUnit.Case, async: false
  import TestUtils
  alias FDB.Transaction
  alias FDB.Cluster
  alias FDB.Database
  alias FDB.Coder.Subspace
  alias FDB.Coder.ByteString
  alias FDB.KeySelector
  alias FDB.KeySelectorRange
  alias FDB.Coder
  use ExUnitProperties

  setup do
    flushdb()
  end

  test "subspace" do
    coder = Transaction.Coder.new(Subspace.new("fdb", ByteString.new()))

    db =
      Cluster.create()
      |> Database.create(%{coder: coder})

    db_raw =
      Cluster.create()
      |> Database.create()

    key = random_key()
    value = random_value()

    Database.transact(db, fn t ->
      Transaction.set(t, key, value)
    end)

    Database.transact(db, fn t ->
      assert Transaction.get(t, key) == value
    end)

    [{stored_key, stored_value}] =
      Transaction.get_range(
        db_raw,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal(<<0x00>>),
          KeySelector.first_greater_or_equal(<<0xFF>>)
        )
      )
      |> Enum.to_list()

    assert stored_value == value
    assert String.starts_with?(stored_key, "fdb")

    all =
      Transaction.get_range(
        db,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal(nil, %{prefix: :first}),
          KeySelector.first_greater_or_equal(nil, %{prefix: :last})
        )
      )
      |> Enum.to_list()

    assert all == [{key, value}]
  end

  property "encode / decode" do
    check all {coder, values} <- generator() do
      assert_coder_order_symmetry(coder, values)
    end
  end

  property "range" do
    check all {coder, values} <- range_generator() do
      Enum.each(values, fn value ->
        Transaction.Coder.encode_range(Transaction.Coder.new(coder), value, :first)
      end)
    end
  end

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

  def generator do
    leaves =
      one_of([
        {constant(Coder.UnicodeString.new()), many(string(@ranges))},
        {constant(Coder.ArbitraryInteger.new()), many(integer())},
        {constant(Coder.ByteString.new()), many(binary())},
        {constant(Coder.UUID.new()), many(binary(length: 16))},
        {constant(Coder.Float.new(32)), many(float32())},
        {constant(Coder.Float.new(64)), many(float())},
        {constant(Coder.Integer.new()), many(integer(-0xFFFFFFFFFFFFFFFF..0xFFFFFFFFFFFFFFFF))},
        {constant(Coder.Versionstamp.new()),
         many(map(binary(length: 12), &FDB.Versionstamp.new(&1)))}
      ])

    tree(leaves, fn leaf ->
      one_of([
        map(list_of(leaf), fn leaves ->
          coders = Enum.map(leaves, &elem(&1, 0)) |> List.to_tuple()
          values = Enum.map(leaves, &elem(&1, 1)) |> Enum.zip()
          {Coder.Tuple.new(coders), values}
        end),
        map(list_of(leaf), fn leaves ->
          coders = Enum.map(leaves, &elem(&1, 0)) |> List.to_tuple()
          values = Enum.map(leaves, &elem(&1, 1)) |> Enum.zip()
          {Coder.NestedTuple.new(coders), values}
        end),
        map(leaf, fn {coder, values} ->
          {Coder.Nullable.new(coder), values}
        end)
      ])
    end)
  end

  def range_generator do
    leaves =
      one_of([
        {constant(Coder.UnicodeString.new()), many(string(@ranges))},
        {constant(Coder.ArbitraryInteger.new()), many(integer())},
        {constant(Coder.ByteString.new()), many(binary())},
        {constant(Coder.UUID.new()), many(binary(length: 16))},
        {constant(Coder.Float.new(32)), many(float32())},
        {constant(Coder.Float.new(64)), many(float())},
        {constant(Coder.Integer.new()), many(integer(-0xFFFFFFFFFFFFFFFF..0xFFFFFFFFFFFFFFFF))},
        {constant(Coder.Boolean.new()), many(boolean())}
      ])

    tree(leaves, fn leaf ->
      one_of([
        map(list_of(leaf), fn leaves ->
          coders = Enum.map(leaves, &elem(&1, 0)) |> List.to_tuple()

          values =
            Enum.map(leaves, &elem(&1, 1))
            |> Enum.zip()
            |> Enum.map(&sublists/1)
            |> Enum.concat()

          {Coder.Tuple.new(coders), values}
        end),
        map(list_of(leaf), fn leaves ->
          coders = Enum.map(leaves, &elem(&1, 0)) |> List.to_tuple()

          values =
            Enum.map(leaves, &elem(&1, 1))
            |> Enum.zip()
            |> Enum.map(&sublists/1)
            |> Enum.concat()

          {Coder.NestedTuple.new(coders), values}
        end),
        bind(leaf, fn {coder, values} ->
          {constant(Coder.Nullable.new(coder)),
           list_of(one_of([nil, member_of([nil] ++ values)]))}
        end)
      ])
    end)
  end

  def sublists(tuple) do
    list = Tuple.to_list(tuple)

    for i <- 0..length(list) do
      Enum.take(list, i) |> List.to_tuple()
    end
  end

  def many(gen) do
    list_of(gen, length: 10)
  end

  def float32 do
    map(float(), fn n ->
      <<n::32-float-big>> = <<n::32-float-big>>
      n
    end)
  end
end
