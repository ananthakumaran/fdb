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
  end
end
