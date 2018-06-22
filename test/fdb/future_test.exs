defmodule FDB.FutureTest do
  use ExUnit.Case, async: false
  alias FDB.Transaction
  alias FDB.Database
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
end
