defmodule FDB.FutureTest do
  use ExUnit.Case, async: false
  alias FDB.Transaction
  alias FDB.Database
  alias FDB.Future
  use FDB.Future.Operators
  import TestUtils

  setup do
    flushdb()
  end

  test "operators" do
    db = new_database()

    Database.transact(db, fn transaction ->
      :ok = Transaction.set(transaction, "A", "A")
      :ok = Transaction.set(transaction, "B", "B")
    end)

    Database.transact(db, fn transaction ->
      a = Transaction.get_q(transaction, "A")
      b = Transaction.get_q(transaction, "B")
      ab = @a <> @b
      Transaction.set(transaction, ab, ab)
    end)

    Database.transact(db, fn transaction ->
      assert Transaction.get(transaction, "AB") == "AB"
    end)
  end

  test "ready?" do
    db = new_database()

    future =
      Database.transact(db, fn t ->
        assert Transaction.set(t, random_key(), random_value()) == :ok
        Transaction.get_versionstamp_q(t)
      end)

    ready = Future.ready?(future)
    assert ready == true || ready == false
    Future.await(future)
    assert Future.ready?(future)
  end

  test "map" do
    db = new_database()

    future =
      Database.transact(db, fn transaction ->
        :ok = Transaction.set(transaction, "A", "A")

        Transaction.get_q(transaction, "A")
        |> Future.map(&(&1 <> "B"))
        |> Future.map(&(&1 <> "C"))
      end)

    assert Future.await(future) == "ABC"
  end
end
