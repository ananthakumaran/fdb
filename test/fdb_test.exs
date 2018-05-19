defmodule FDBTest do
  use ExUnit.Case, async: false
  import FDB
  import FDB.Option
  import TestUtils

  setup do
    flushdb
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
end
