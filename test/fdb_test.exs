defmodule FDBTest do
  use ExUnit.Case, async: false
  import FDB.Option
  import TestUtils
  alias FDB.KeySelector
  alias FDB.Database
  alias FDB.Cluster
  alias FDB.Transaction
  alias FDB.Network
  alias FDB.Future

  setup do
    flushdb()
  end

  test "transaction" do
    value = random_value()
    key = random_key()
    db = new_database()

    Transaction.transact(db, fn transaction ->
      Transaction.set(transaction, key, value)
      assert Transaction.get(transaction, key) == value
    end)

    Transaction.transact(db, fn transaction ->
      assert Transaction.get(transaction, key) == value
      assert Transaction.clear(transaction, key) == :ok
    end)

    Transaction.transact(db, fn transaction ->
      assert Transaction.get(transaction, key) == nil
    end)
  end

  test "options" do
    assert_raise ErlangError, ~r/value/, fn -> Cluster.set_option(Cluster.create(), 5, :ok) end
    assert_raise ErlangError, ~r/option/, fn -> Cluster.set_option(Cluster.create(), :ok) end
    assert_raise ErlangError, ~r/cluster/, fn -> Cluster.set_option(0, 0) end
    assert_raise ErlangError, ~r/option/, fn -> Transaction.set_option(new_transaction(), :ok) end
    assert_raise ErlangError, ~r/transaction/, fn -> Transaction.set_option(0, 0) end

    assert_raise ErlangError, ~r/value/, fn ->
      Transaction.set_option(new_transaction(), 5, :ok)
    end

    assert_raise ErlangError, ~r/option/, fn -> Database.set_option(new_database(), :ok) end
    assert_raise ErlangError, ~r/value/, fn -> Database.set_option(new_database(), 5, :ok) end
    assert_raise ErlangError, ~r/database/, fn -> Database.set_option(0, 0) end
    assert_raise ErlangError, ~r/value/, fn -> Network.set_option(0, :ok) end

    db = new_database()
    assert Database.set_option(db, database_option_datacenter_id(), "DATA_CENTER_42") == :ok
  end

  test "timeout" do
    t = new_transaction()
    assert Transaction.set_option(t, transaction_option_timeout(), 1) == :ok
    :timer.sleep(1)
    key = random_key()
    assert_raise FDB.Error, ~r/timed out/, fn -> Transaction.get(t, key) end
    assert_raise FDB.Error, ~r/timed out/, fn -> Transaction.commit(t) end
  end

  test "reuse transaction" do
    t = new_transaction()

    value = random_value()
    key = random_key()
    Transaction.set(t, key, value)
    assert Transaction.get(t, key) == value
    assert Transaction.commit(t) == :ok

    assert_raise FDB.Error, ~r/commit/, fn -> Transaction.get(t, key) end
  end

  test "range" do
    d = new_database()

    expected =
      Transaction.transact(d, fn t ->
        Enum.map(1..100, fn i ->
          key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
          value = random_value(100)
          Transaction.set(t, key, value)
          {key, value}
        end)
      end)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc")
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{reverse: 1}
      )
      |> Enum.to_list()

    assert actual == Enum.reverse(expected)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 10}
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 10, reverse: 1}
      )
      |> Enum.to_list()

    assert actual == Enum.take(Enum.reverse(expected), 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_or_equal("fdb:011"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_than("fdb:010"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_or_equal("fdb:000"),
        KeySelector.first_greater_or_equal("fdb:011")
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelector.first_greater_or_equal("fdb:000"),
        KeySelector.first_greater_or_equal("fdb:011"),
        %{reverse: 1}
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10) |> Enum.reverse()
  end

  test "atomic_op" do
    t = new_transaction()
    Transaction.set(t, "fdb:counter", <<0::little-integer-unsigned-size(64)>>)
    assert Transaction.commit(t) == :ok

    t = new_transaction()

    Transaction.atomic_op(
      t,
      "fdb:counter",
      <<1::little-integer-unsigned-size(64)>>,
      mutation_type_add()
    )

    assert Transaction.commit(t) == :ok

    t = new_transaction()
    <<counter::little-integer-unsigned-size(64)>> = Transaction.get(t, "fdb:counter")
    assert counter == 1
    assert Transaction.commit(t) == :ok

    t = new_transaction()

    Transaction.atomic_op(
      t,
      "fdb:counter",
      <<5::little-integer-unsigned-size(64)>>,
      mutation_type_add()
    )

    assert Transaction.commit(t) == :ok

    t = new_transaction()
    <<counter::little-integer-unsigned-size(64)>> = Transaction.get(t, "fdb:counter")
    assert counter == 6
    assert Transaction.commit(t) == :ok
  end

  test "version" do
    db = new_database()

    version =
      Transaction.transact(db, fn t ->
        version = Transaction.get_read_version(t)
        assert version > 0
        assert Transaction.get_read_version(t) == version
        version
      end)

    Transaction.transact(db, fn t ->
      Transaction.set(t, random_key(), random_value())
    end)

    Transaction.transact(db, fn t ->
      assert Transaction.get_read_version(t) > version
    end)

    Transaction.transact(db, fn t ->
      assert Transaction.set_read_version(t, version) == :ok
    end)

    Transaction.transact(db, fn t ->
      assert Transaction.set_read_version(t, version + 1000) == :ok
      assert Transaction.get(t, random_key()) == nil
    end)

    t = new_transaction()
    assert Transaction.set_read_version(t, version + 1000_000_000) == :ok
    assert_raise FDB.Error, fn -> Transaction.get(t, random_key()) == nil end
  end

  test "get_key" do
    t = new_transaction()

    Enum.each(1..100, fn i ->
      key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
      value = random_value(100)
      assert Transaction.set(t, key, value) == :ok
      {key, value}
    end)

    assert Transaction.commit(t) == :ok

    t = new_transaction()
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:000")) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001")) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", 0)) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", 1)) == "fdb:002"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", 10)) == "fdb:011"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", -1)) == "fdb:009"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", -9)) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", -10)) == ""
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:001")) == "fdb:002"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:001", 1)) == "fdb:003"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:002", 5)) == "fdb:008"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", -1)) == "fdb:005"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", -2)) == "fdb:004"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", -5)) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", -6)) == ""
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", -10)) == ""

    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050")) == "fdb:049"
    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050", 5)) == "fdb:054"
    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050", -5)) == "fdb:044"
    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050")) == "fdb:050"
    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050", 5)) == "fdb:055"
    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050", -5)) == "fdb:045"
  end

  test "addresses" do
    db = new_database()

    Transaction.transact(db, fn t ->
      Enum.each(1..100, fn i ->
        key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
        value = random_value(100)
        assert Transaction.set(t, key, value) == :ok
        {key, value}
      end)
    end)

    Transaction.transact(db, fn t ->
      addresses = Transaction.get_addresses_for_key(t, "fdb:001")
      assert length(addresses) == 1
      assert Transaction.get_addresses_for_key(t, "fdb:100") == addresses
      assert Transaction.get_addresses_for_key(t, "unknown") == addresses
    end)
  end

  test "commited version" do
    t = new_transaction()
    Transaction.set(t, random_key(), random_value())
    assert Transaction.commit(t) == :ok
    v1 = Transaction.get_committed_version(t)
    assert v1 > 0

    t = new_transaction()
    Transaction.set(t, random_key(), random_value())
    assert Transaction.commit(t) == :ok
    v2 = Transaction.get_committed_version(t)
    assert v2 > 0
    assert v2 > v1

    t = new_transaction()
    Transaction.get(t, random_key())
    assert Transaction.commit(t) == :ok
    read_only_version = Transaction.get_committed_version(t)
    assert read_only_version == -1
  end

  test "versionstamp" do
    db = new_database()

    future =
      Transaction.transact(db, fn t ->
        assert Transaction.set(t, random_key(), random_value()) == :ok
        Transaction.get_versionstamp(t)
      end)

    stamp = Future.resolve(future)
    assert byte_size(stamp) == 10

    future =
      Transaction.transact(db, fn t ->
        Transaction.get(t, random_key())
        Transaction.get_versionstamp(t)
      end)

    assert_raise FDB.Error, ~r/read-only/, fn -> Future.resolve(future) end
  end

  test "watch" do
    value = random_value()
    key = random_key()
    db = new_database()

    Transaction.transact(db, fn t ->
      assert Transaction.set(t, key, value) == :ok
    end)

    w1 =
      Transaction.transact(db, fn t ->
        assert Transaction.get(t, key) == value
        Transaction.watch(t, key)
      end)

    Transaction.transact(db, fn t ->
      assert Transaction.set(t, key, random_value()) == :ok
    end)

    assert Future.resolve(w1) == :ok
  end

  test "transact" do
    db = new_database()
    key = random_key()

    Task.async_stream(
      1..100,
      fn _i ->
        Transaction.transact(db, fn transaction ->
          value = random_value()
          _current = Transaction.get(transaction, key)
          Transaction.set(transaction, key, value)
          assert Transaction.get(transaction, key) == value
        end)
      end,
      max_concurrency: 10,
      ordered: false
    )
    |> Stream.run()
  end
end
