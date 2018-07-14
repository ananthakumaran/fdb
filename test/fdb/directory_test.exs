defmodule FDB.DirectoryTest do
  use ExUnit.Case, async: false
  import TestUtils
  alias FDB.Directory.HighContentionAllocator
  alias FDB.Directory
  alias FDB.Database
  use ExUnitProperties

  setup do
    flushdb()
  end

  property "unique" do
    check all count <- integer(1..1500),
              concurrency <- integer(1..100),
              max_run_time: 3000 do
      :ok = flushdb()

      database = new_database()
      root = Directory.new()

      dirs =
        Task.async_stream(
          1..count,
          fn _ ->
            Database.transact(database, fn t ->
              HighContentionAllocator.allocate(
                root,
                t
              )
            end)
          end,
          max_concurrency: concurrency
        )
        |> Enum.map(fn {:ok, dir} -> dir end)

      assert length(dirs) == length(Enum.uniq(dirs))
    end
  end

  test "create" do
    database = new_database()
    root = Directory.new()

    Database.transact(database, fn tr ->
      usa = Directory.create(root, tr, ["usa"])
      assert Directory.list(usa, tr) == []
      arizona = Directory.create(usa, tr, ["arizona"])
      assert Directory.list(usa, tr) == ["arizona"]
      assert Directory.list(arizona, tr) == []
      usa = Directory.open(root, tr, ["usa"])
      assert Directory.list(usa, tr) == ["arizona"]
    end)
  end
end
