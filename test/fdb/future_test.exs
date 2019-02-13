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

  test "then" do
    db = new_database()

    Database.transact(db, fn transaction ->
      :ok = Transaction.set(transaction, "A", "B")
      :ok = Transaction.set(transaction, "B", "C")
      :ok = Transaction.set(transaction, "C", "D")
    end)

    Database.transact(db, fn transaction ->
      future =
        Transaction.get_q(transaction, "A")
        |> Future.then(fn ptr ->
          Transaction.get_q(transaction, ptr)
        end)
        |> Future.then(fn ptr ->
          Transaction.get_q(transaction, ptr)
        end)

      assert Future.await(future) == "D"
    end)

    Database.transact(db, fn transaction ->
      future =
        Transaction.get_q(transaction, "A")
        |> Future.then(fn ptr ->
          Transaction.get_q(transaction, ptr)
        end)
        |> Future.then(fn ptr ->
          Transaction.get_q(transaction, ptr)
        end)
        |> Future.then(fn x -> x <> "end" end)

      assert Future.await(future) == "Dend"
    end)
  end

  test "constant" do
    db = new_database()

    Database.transact(db, fn transaction ->
      :ok = Transaction.set(transaction, "A", "A")
    end)

    Database.transact(db, fn transaction ->
      future =
        Future.constant("A")
        |> Future.then(fn ptr ->
          Transaction.get_q(transaction, ptr)
        end)

      assert Future.await(future) == "A"
      assert Future.ready?(future)
    end)

    assert Future.await(Future.constant("A")) == "A"
    assert Future.ready?(Future.constant("A"))
  end

  test "all" do
    db = new_database()

    Database.transact(db, fn transaction ->
      :ok = Transaction.set(transaction, "A", "B")
      :ok = Transaction.set(transaction, "B", "C")
      :ok = Transaction.set(transaction, "C", "D")
    end)

    Database.transact(db, fn transaction ->
      future =
        Future.all([
          Transaction.get_q(transaction, "A"),
          Transaction.get_q(transaction, "B"),
          Transaction.get_q(transaction, "C")
        ])

      assert Future.await(future) == ["B", "C", "D"]
    end)
  end
end
