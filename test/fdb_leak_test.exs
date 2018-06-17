defmodule FDBLeakTest do
  use ExUnit.Case
  import TestUtils
  require Logger
  alias FDB.Database
  alias FDB.Cluster
  alias FDB.Transaction

  setup do
    flushdb()
  end

  @tag timeout: 300_000, integration: true
  test "memory leak" do
    assert_memory()

    db =
      Cluster.create()
      |> Database.create()

    Task.async_stream(
      1..100_000,
      fn i ->
        if Integer.mod(i, 1000) == 0 do
          :ok = flushdb()
        end

        # 10 KB * 100_000 => 1000 MB
        value = random_value(10 * 1024)
        key = random_key(64)

        t = Transaction.create(db)
        Transaction.set(t, key, value)
        assert Transaction.get(t, key) == value
        assert Transaction.commit(t) == :ok
      end,
      max_concurrency: 200,
      ordered: false,
      timeout: 30_000
    )
    |> Stream.run()

    assert_memory()
  end

  test "resource early garbage collection" do
    parent = self()

    # A temp process is used to trigger garbage collection of cluster
    # & database. Transaction should keep a reference to them and
    # avoid early garbage collection by erts
    spawn_link(fn ->
      t =
        Cluster.create()
        |> Database.create()
        |> Transaction.create()

      send(parent, t)
    end)

    receive do
      t ->
        :ok = Transaction.set_option(t, FDB.Option.transaction_option_access_system_keys())
        assert Transaction.get(t, "\xff\xff/status/json")
        assert Transaction.get(t, "\xff\xff/cluster_file_path")
    end
  end

  def assert_memory do
    Enum.each(Process.list(), fn pid -> :erlang.garbage_collect(pid) end)
    total = (:erlang.memory() |> Keyword.fetch!(:total)) / (1024 * 1024)
    Logger.debug("Total memory: #{total}")
    assert total < 150
  end
end
