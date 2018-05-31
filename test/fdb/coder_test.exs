defmodule FDB.CoderTest do
  use ExUnit.Case, async: false
  import TestUtils
  alias FDB.Transaction
  alias FDB.Cluster
  alias FDB.Database
  alias FDB.Coder.Subspace
  alias FDB.Coder.ByteString
  alias FDB.KeySelector

  setup do
    flushdb()
  end

  test "subspace" do
    coder = %Transaction.Coder{key: Subspace.new("fdb", ByteString.new())}

    db =
      Cluster.create()
      |> Database.create(coder)

    db_raw =
      Cluster.create()
      |> Database.create()

    key = random_key()
    value = random_value()

    Transaction.transact(db, fn t ->
      Transaction.set(t, key, value)
    end)

    Transaction.transact(db, fn t ->
      assert Transaction.get(t, key) == value
    end)

    [{stored_key, stored_value}] =
      Transaction.get_range_stream(
        db_raw,
        KeySelector.first_greater_or_equal(<<0x00>>),
        KeySelector.first_greater_or_equal(<<0xFF>>)
      )
      |> Enum.to_list()

    assert stored_value == value
    assert String.starts_with?(stored_key, "fdb")

    all =
      Transaction.get_range_stream(
        db,
        KeySelector.first_greater_or_equal(nil),
        KeySelector.first_greater_or_equal(nil)
      )
      |> Enum.to_list()

    assert all == [{key, value}]
  end
end
