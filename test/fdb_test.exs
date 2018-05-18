defmodule FDBTest do
  use ExUnit.Case
  import FDB

  test "create cluster" do
    cluster = create_cluster()
    assert cluster
    database = create_database(cluster)
    assert database
    transaction = create_transaction(database)
    assert transaction
    value = get(transaction, "hello")
    assert value
    value = get(transaction, "unknown")
    assert !value
    value = get_snapshot(transaction, "hello")
    assert value
    value = get_snapshot(transaction, "unknown")
    assert !value
  end

  test "transaction" do
    transaction = new_transaction

    value = random_bytes()
    set(transaction, "fdb", value)
    assert get(transaction, "fdb") == value
    assert commit(transaction) == :ok

    transaction = new_transaction
    assert get(transaction, "fdb") == value
    assert clear(transaction, "fdb") == :ok
    assert commit(transaction) == :ok

    transaction = new_transaction
    assert get(transaction, "fdb") == nil
  end

  def new_transaction do
    create_cluster()
    |> create_database()
    |> create_transaction()
  end

  def random_bytes() do
    :crypto.strong_rand_bytes(1024)
  end
end
