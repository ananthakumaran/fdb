defmodule FDBTest do
  use ExUnit.Case, async: false
  import FDB.Option
  import TestUtils
  alias FDB.KeySelector
  alias FDB.KeyRange
  alias FDB.KeySelectorRange
  alias FDB.Transaction
  alias FDB.Future
  alias FDB.Database
  alias FDB.Versionstamp
  alias FDB.Coder

  setup do
    flushdb()
  end

  test "transaction" do
    value = random_value()
    key = random_key()
    db = new_database()

    Database.transact(db, fn transaction ->
      Transaction.set(transaction, key, value)
      assert Transaction.get(transaction, key) == value
    end)

    Database.transact(db, fn transaction ->
      assert Transaction.get(transaction, key) == value
      assert Transaction.clear(transaction, key) == :ok
    end)

    Database.transact(db, fn transaction ->
      assert Transaction.get(transaction, key) == nil
    end)
  end

  test "cluster path" do
    assert_raise(FDB.Error, ~r/file/, fn -> Database.create("/hello/world") end)
  end

  test "timeout" do
    t = new_transaction()
    assert Transaction.set_option(t, transaction_option_timeout(), 1) == :ok
    :timer.sleep(2)
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
      Database.transact(d, fn t ->
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
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb"),
          KeySelector.first_greater_than("fdc")
        )
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb"),
          KeySelector.first_greater_than("fdc")
        ),
        %{reverse: true}
      )
      |> Enum.to_list()

    assert actual == Enum.reverse(expected)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb"),
          KeySelector.first_greater_than("fdc")
        ),
        %{limit: 10}
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb"),
          KeySelector.first_greater_than("fdc")
        ),
        %{limit: 10, reverse: true, snapshot: true}
      )
      |> Enum.to_list()

    assert actual == Enum.take(Enum.reverse(expected), 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb"),
          KeySelector.first_greater_than("fdc")
        ),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == expected

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal("fdb:011"),
          KeySelector.first_greater_than("fdc")
        ),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_than("fdb:010"),
          KeySelector.first_greater_than("fdc")
        ),
        %{limit: 1000}
      )
      |> Enum.to_list()

    assert actual == Enum.drop(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal("fdb:000"),
          KeySelector.first_greater_or_equal("fdb:011")
        )
      )
      |> Enum.to_list()

    assert actual == Enum.take(expected, 10)

    actual =
      Transaction.get_range_stream(
        d,
        KeySelectorRange.range(
          KeySelector.first_greater_or_equal("fdb:000"),
          KeySelector.first_greater_or_equal("fdb:011")
        ),
        %{reverse: true}
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
      mutation_type_add(),
      <<1::little-integer-unsigned-size(64)>>
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
      mutation_type_add(),
      <<5::little-integer-unsigned-size(64)>>
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
      Database.transact(db, fn t ->
        version = Transaction.get_read_version(t)
        assert version > 0
        assert Transaction.get_read_version(t) == version
        version
      end)

    Database.transact(db, fn t ->
      Transaction.set(t, random_key(), random_value())
    end)

    Database.transact(db, fn t ->
      assert Transaction.get_read_version(t) > version
    end)

    Database.transact(db, fn t ->
      assert Transaction.set_read_version(t, version) == :ok
    end)

    Database.transact(db, fn t ->
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
    assert Transaction.get_key(t, KeySelector.last_less_or_equal("a")) == <<>>
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("z")) == <<0xFF>>
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:000")) == "fdb:001"
    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001")) == "fdb:001"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", %{offset: 0})) ==
             "fdb:001"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", %{offset: 1})) ==
             "fdb:002"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:001", %{offset: 10})) ==
             "fdb:011"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", %{offset: -1})) ==
             "fdb:009"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", %{offset: -9})) ==
             "fdb:001"

    assert Transaction.get_key(t, KeySelector.first_greater_or_equal("fdb:010", %{offset: -10})) ==
             ""

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:001")) == "fdb:002"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:001", %{offset: 1})) ==
             "fdb:003"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:002", %{offset: 5})) ==
             "fdb:008"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", %{offset: -1})) ==
             "fdb:005"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", %{offset: -2})) ==
             "fdb:004"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", %{offset: -5})) ==
             "fdb:001"

    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", %{offset: -6})) == ""
    assert Transaction.get_key(t, KeySelector.first_greater_than("fdb:005", %{offset: -10})) == ""

    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050")) == "fdb:049"

    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050", %{offset: 5})) ==
             "fdb:054"

    assert Transaction.get_key(t, KeySelector.last_less_than("fdb:050", %{offset: -5})) ==
             "fdb:044"

    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050")) == "fdb:050"

    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050", %{offset: 5})) ==
             "fdb:055"

    assert Transaction.get_key(t, KeySelector.last_less_or_equal("fdb:050", %{offset: -5})) ==
             "fdb:045"
  end

  test "addresses" do
    db = new_database()

    Database.transact(db, fn t ->
      Enum.each(1..100, fn i ->
        key = "fdb:" <> String.pad_leading(Integer.to_string(i), 3, "0")
        value = random_value(100)
        assert Transaction.set(t, key, value) == :ok
        {key, value}
      end)
    end)

    Database.transact(db, fn t ->
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
      Database.transact(db, fn t ->
        assert Transaction.set(t, random_key(), random_value()) == :ok
        Transaction.get_versionstamp_q(t)
      end)

    stamp = Future.await(future)
    assert byte_size(Versionstamp.transaction_version(stamp)) == 10
    assert Versionstamp.user_version(stamp) == 0

    future =
      Database.transact(db, fn t ->
        Transaction.get(t, random_key())
        Transaction.get_versionstamp_q(t)
      end)

    assert_raise FDB.Error, ~r/read-only/, fn -> Future.await(future) end
  end

  test "versionstamped key" do
    coder =
      FDB.Transaction.Coder.new(
        Coder.Tuple.new({Coder.ByteString.new(), Coder.Versionstamp.new()})
      )

    db =
      new_database()
      |> Database.set_defaults(%{coder: coder})

    future =
      Database.transact(db, fn t ->
        assert Transaction.set_versionstamped_key(
                 t,
                 {"stamped", FDB.Versionstamp.incomplete()},
                 random_value()
               ) == :ok

        Transaction.get_versionstamp_q(t)
      end)

    stamp = Future.await(future)
    assert Versionstamp.user_version(stamp) == 0

    [{{"stamped", key_stamp}, _}] =
      Database.get_range_stream(db, KeySelectorRange.starts_with({"stamped"}))
      |> Enum.to_list()

    assert stamp == key_stamp

    Database.transact(db, fn t ->
      assert_raise(ArgumentError, ~r/no/i, fn ->
        Transaction.set_versionstamped_key(
          t,
          {"stamped", nil},
          random_value()
        )
      end)

      assert_raise(ArgumentError, ~r/more/i, fn ->
        Transaction.set_versionstamped_key(
          t,
          {FDB.Versionstamp.incomplete(), FDB.Versionstamp.incomplete()},
          random_value()
        )
      end)
    end)
  end

  test "versionstamped key with subspace" do
    coder = FDB.Transaction.Coder.new(Coder.Subspace.new("stamped", Coder.Versionstamp.new()))

    db =
      new_database()
      |> Database.set_defaults(%{coder: coder})

    future =
      Database.transact(db, fn t ->
        assert Transaction.set_versionstamped_key(
                 t,
                 FDB.Versionstamp.incomplete(),
                 random_value()
               ) == :ok

        Transaction.get_versionstamp_q(t)
      end)

    stamp = Future.await(future)
    assert Versionstamp.user_version(stamp) == 0

    [{key_stamp, _}] =
      Database.get_range_stream(db, KeySelectorRange.starts_with(nil))
      |> Enum.to_list()

    assert stamp == key_stamp
  end

  test "versionstamped value" do
    coder =
      FDB.Transaction.Coder.new(
        Coder.ByteString.new(),
        Coder.Tuple.new({Coder.ByteString.new(), Coder.Versionstamp.new()})
      )

    db =
      new_database()
      |> Database.set_defaults(%{coder: coder})

    key = random_key()

    future =
      Database.transact(db, fn t ->
        :ok =
          Transaction.set_versionstamped_value(
            t,
            key,
            {"stamped", FDB.Versionstamp.incomplete()}
          )

        Transaction.get_versionstamp_q(t)
      end)

    stamp = Future.await(future)
    assert Versionstamp.user_version(stamp) == 0

    value =
      Database.transact(db, fn t ->
        Transaction.get(t, key)
      end)

    assert {"stamped", stamp} == value
  end

  test "watch" do
    value = random_value()
    key = random_key()
    db = new_database()

    Database.transact(db, fn t ->
      assert Transaction.set(t, key, value) == :ok
    end)

    w1 =
      Database.transact(db, fn t ->
        assert Transaction.get(t, key) == value
        Transaction.watch_q(t, key)
      end)

    Database.transact(db, fn t ->
      assert Transaction.set(t, key, random_value()) == :ok
    end)

    assert Future.await(w1) == :ok
  end

  test "transact" do
    db = new_database()
    key = random_key()

    Task.async_stream(
      1..100,
      fn _i ->
        Database.transact(db, fn transaction ->
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

  test "conflict range" do
    value = random_value()
    key = random_key()
    db = new_database()

    Database.transact(db, fn transaction ->
      range = KeyRange.starts_with("fdb:")
      :ok = Transaction.add_conflict_range(transaction, range, conflict_range_type_read())
      :ok = Transaction.add_conflict_range(transaction, range, conflict_range_type_write())

      Transaction.set(transaction, key, value)
      assert Transaction.get(transaction, key) == value
    end)
  end

  test "metadata version" do
    db = new_database()

    old =
      Database.transact(db, fn t ->
        Transaction.get_metadata_version(t)
      end)

    Database.transact(db, fn t ->
      Transaction.update_metadata_version(t)
    end)

    new =
      Database.transact(db, fn t ->
        Transaction.get_metadata_version(t)
      end)

    assert new != nil
    assert old != new
  end
end
