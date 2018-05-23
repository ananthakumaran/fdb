defmodule FDBTest do
  use ExUnit.Case, async: false
  import FDB
  import FDB.Option
  import TestUtils
  alias FDB.KeySelector

  setup do
    flushdb()
  end

  test "transaction" do
    value = random_value()
    key = random_key()

    transaction = new_transaction()
    set(transaction, key, value)
    assert get(transaction, key) == value
    assert commit(transaction) == :ok

    transaction = new_transaction()
    assert get(transaction, key) == value
    assert clear(transaction, key) == :ok
    assert commit(transaction) == :ok

    transaction = new_transaction()
    assert get(transaction, key) == nil
    assert commit(transaction) == :ok
  end

  test "options" do
    assert_raise ErlangError, ~r/value/, fn -> cluster_set_option(create_cluster(), 5, :ok) end
    assert_raise ErlangError, ~r/option/, fn -> cluster_set_option(create_cluster(), :ok) end
    assert_raise ErlangError, ~r/cluster/, fn -> cluster_set_option(0, 0) end
    assert_raise ErlangError, ~r/option/, fn -> transaction_set_option(new_transaction(), :ok) end
    assert_raise ErlangError, ~r/transaction/, fn -> transaction_set_option(0, 0) end

    assert_raise ErlangError, ~r/value/, fn ->
      transaction_set_option(new_transaction(), 5, :ok)
    end

    assert_raise ErlangError, ~r/option/, fn -> database_set_option(new_database(), :ok) end
    assert_raise ErlangError, ~r/value/, fn -> database_set_option(new_database(), 5, :ok) end
    assert_raise ErlangError, ~r/database/, fn -> database_set_option(0, 0) end
    assert_raise ErlangError, ~r/value/, fn -> network_set_option(0, :ok) end

    db = new_database()
    assert database_set_option(db, database_option_datacenter_id(), "DATA_CENTER_42") == :ok
  end

  test "timeout" do
    t = new_transaction()
    assert transaction_set_option(t, transaction_option_timeout(), 1) == :ok
    :timer.sleep(1)
    key = random_key()
    assert_raise FDB.Error, ~r/timed out/, fn -> get(t, key) end
    assert_raise FDB.Error, ~r/timed out/, fn -> commit(t) end
  end

  test "reuse transaction" do
    t = new_transaction()

    value = random_value()
    key = random_key()
    set(t, key, value)
    assert get(t, key) == value
    assert commit(t) == :ok

    assert_raise FDB.Error, ~r/commit/, fn -> get(t, key) end
  end

  test "range" do
    t = new_transaction()

    expected =
      Enum.map(1..100, fn i ->
        key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
        value = random_value(100)
        set(t, key, value)
        {key, value}
      end)

    assert commit(t) == :ok

    d = new_database()

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc")
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{reverse: 1}
      )
      |> Enum.to_list()

    assert actual == Enum.reverse(expected)

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 10}
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 10, reverse: 1}
      )
      |> Enum.to_list()

    assert actual == Enum.take(Enum.reverse(expected), 10)

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_or_equal("fdb:011"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_than("fdb:010"),
        KeySelector.first_greater_than("fdc"),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      get_range_stream(
        d,
        KeySelector.first_greater_or_equal("fdb:000"),
        KeySelector.first_greater_or_equal("fdb:011")
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      get_range_stream(
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
    set(t, "fdb:counter", <<0::little-integer-unsigned-size(64)>>)
    assert commit(t) == :ok

    t = new_transaction()

    atomic_op(
      t,
      "fdb:counter",
      <<1::little-integer-unsigned-size(64)>>,
      mutation_type_add()
    )

    assert commit(t) == :ok

    t = new_transaction()
    <<counter::little-integer-unsigned-size(64)>> = get(t, "fdb:counter")
    assert counter == 1
    assert commit(t) == :ok

    t = new_transaction()

    atomic_op(
      t,
      "fdb:counter",
      <<5::little-integer-unsigned-size(64)>>,
      mutation_type_add()
    )

    assert commit(t) == :ok

    t = new_transaction()
    <<counter::little-integer-unsigned-size(64)>> = get(t, "fdb:counter")
    assert counter == 6
    assert commit(t) == :ok
  end

  test "version" do
    t = new_transaction()
    version = get_read_version(t)
    assert version > 0
    assert get_read_version(t) == version

    t = new_transaction()
    set(t, random_key(), random_value())
    assert commit(t) == :ok

    t = new_transaction()
    assert get_read_version(t) > version

    t = new_transaction()
    assert set_read_version(t, version) == :ok

    t = new_transaction()
    assert set_read_version(t, version + 1000) == :ok
    assert get(t, random_key()) == nil

    t = new_transaction()
    assert set_read_version(t, version + 1000_000_000) == :ok
    assert_raise FDB.Error, fn -> get(t, random_key()) == nil end
  end

  test "get_key" do
    t = new_transaction()

    Enum.each(1..100, fn i ->
      key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
      value = random_value(100)
      assert set(t, key, value) == :ok
      {key, value}
    end)

    assert commit(t) == :ok

    t = new_transaction()
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:000")) == "fdb:001"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:001")) == "fdb:001"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:001", 0)) == "fdb:001"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:001", 1)) == "fdb:002"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:001", 10)) == "fdb:011"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:010", -1)) == "fdb:009"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:010", -9)) == "fdb:001"
    assert get_key(t, KeySelector.first_greater_or_equal("fdb:010", -10)) == ""
    assert get_key(t, KeySelector.first_greater_than("fdb:001")) == "fdb:002"
    assert get_key(t, KeySelector.first_greater_than("fdb:001", 1)) == "fdb:003"
    assert get_key(t, KeySelector.first_greater_than("fdb:002", 5)) == "fdb:008"
    assert get_key(t, KeySelector.first_greater_than("fdb:005", -1)) == "fdb:005"
    assert get_key(t, KeySelector.first_greater_than("fdb:005", -2)) == "fdb:004"
    assert get_key(t, KeySelector.first_greater_than("fdb:005", -5)) == "fdb:001"
    assert get_key(t, KeySelector.first_greater_than("fdb:005", -6)) == ""
    assert get_key(t, KeySelector.first_greater_than("fdb:005", -10)) == ""

    assert get_key(t, KeySelector.last_less_than("fdb:050")) == "fdb:049"
    assert get_key(t, KeySelector.last_less_than("fdb:050", 5)) == "fdb:054"
    assert get_key(t, KeySelector.last_less_than("fdb:050", -5)) == "fdb:044"
    assert get_key(t, KeySelector.last_less_or_equal("fdb:050")) == "fdb:050"
    assert get_key(t, KeySelector.last_less_or_equal("fdb:050", 5)) == "fdb:055"
    assert get_key(t, KeySelector.last_less_or_equal("fdb:050", -5)) == "fdb:045"
  end

  test "addresses" do
    t = new_transaction()

    Enum.each(1..100, fn i ->
      key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
      value = random_value(100)
      assert set(t, key, value) == :ok
      {key, value}
    end)

    assert commit(t) == :ok

    t = new_transaction()
    addresses = get_addresses_for_key(t, "fdb:001")
    assert length(addresses) == 1
    assert get_addresses_for_key(t, "fdb:100") == addresses
    assert get_addresses_for_key(t, "unknown") == addresses
  end
end
