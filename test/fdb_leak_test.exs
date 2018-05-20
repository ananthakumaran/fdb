defmodule FDBLeakTest do
  use ExUnit.Case
  import FDB
  import TestUtils
  require Logger

  setup do
    flushdb()
  end

  @tag timeout: 300_000, integration: true
  test "memory leak" do
    assert_memory()

    db =
      create_cluster()
      |> create_database()

    Task.async_stream(
      1..100_000,
      fn i ->
        if Integer.mod(i, 1000) == 0 do
          :ok = flushdb()
        end

        # 10 KB * 100_000 => 1000 MB
        value = random_value(10 * 1024)
        key = random_key(64)

        t = create_transaction(db)
        set(t, key, value)
        assert get(t, key) == value
        assert commit(t) == :ok
      end,
      max_concurrency: 200,
      ordered: false,
      timeout: 30_000
    )
    |> Stream.run()

    assert_memory()
  end

  def assert_memory do
    Enum.each(Process.list(), fn pid -> :erlang.garbage_collect(pid) end)
    total = (:erlang.memory() |> Keyword.fetch!(:total)) / (1024 * 1024)
    Logger.debug("Total memory: #{total}")
    assert total < 150
  end
end
