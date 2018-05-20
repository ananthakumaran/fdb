:ok = FDB.start()
ExUnit.start(exclude: [:integration])

System.at_exit(fn _exit_code ->
  :ok = FDB.stop()
end)

defmodule TestUtils do
  import FDB

  def flushdb do
    t = new_transaction()
    :ok = clear_range(t, "", <<0xFF>>)
    commit(t)
  end

  def random_value(size \\ 1024) do
    :crypto.strong_rand_bytes(size)
  end

  def random_key(size \\ 1024) do
    "fdb:" <> :crypto.strong_rand_bytes(size)
  end

  def new_transaction do
    create_cluster()
    |> create_database()
    |> create_transaction()
  end

  def new_database do
    create_cluster()
    |> create_database()
  end
end
