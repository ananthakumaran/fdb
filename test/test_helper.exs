:ok = FDB.Network.start()
ExUnit.start(exclude: [:integration])

System.at_exit(fn _exit_code ->
  :ok = FDB.Network.stop()
end)

defmodule TestUtils do
  alias FDB.Database
  alias FDB.Cluster
  alias FDB.Transaction
  alias FDB.Transaction.Coder

  require ExUnit.Assertions
  import ExUnit.Assertions

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

  def sort_order(value) do
    Enum.with_index(value)
    |> Enum.sort_by(fn {value, _index} -> value end)
    |> Enum.map(fn {_value, index} -> index end)
  end

  def assert_coder_order_symmetry(coder, values) do
    coder = %Transaction.Coder{key: coder}

    encoded =
      Enum.map(values, fn binary ->
        Coder.encode_key(coder, binary)
      end)

    decoded =
      Enum.map(encoded, fn key ->
        Coder.decode_key(coder, key)
      end)

    assert values == decoded
    assert sort_order(values) == sort_order(encoded)
  end
end
