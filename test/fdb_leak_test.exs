defmodule FDBLeakTest do
  use ExUnit.Case
  import FDB
  import TestUtils
  require Logger

  setup do
    flushdb
  end

  test "leak" do
    assert_memory()
    Task.async_stream(1..10_000, fn _ ->
      value = random_value(75 * 1024)
      key = random_key()

      transaction = new_transaction()
      set(transaction, key, value)
      assert get(transaction, key) == value
      assert commit(transaction) == :ok
    end, max_concurrency: 1000, ordered: false)
    |> Stream.run
    assert_memory()
  end

  def assert_memory do
    total = (:erlang.memory() |> Keyword.fetch!(:total)) / (1024 * 1024)
    Logger.debug "Total memory: #{total}"
    assert total < 150
  end
end
