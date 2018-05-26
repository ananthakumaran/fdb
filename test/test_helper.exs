:ok = FDB.Network.start()
ExUnit.start(exclude: [:integration])

System.at_exit(fn _exit_code ->
  :ok = FDB.Network.stop()
end)

defmodule TestUtils do
  alias FDB.Database
  alias FDB.Cluster
  alias FDB.Transaction

  def flushdb do
    t = new_transaction()
    :ok = Transaction.clear_range(t, "", <<0xFF>>)
    Transaction.commit(t)
  end

  def random_value(size \\ 1024) do
    :crypto.strong_rand_bytes(size)
  end

  def random_key(size \\ 1024) do
    "fdb:" <> :crypto.strong_rand_bytes(size)
  end

  def new_transaction do
    Cluster.create()
    |> Database.create()
    |> Transaction.create()
  end

  def new_database do
    Cluster.create()
    |> Database.create()
  end
end
