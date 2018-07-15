defmodule FDB.DirectoryTest do
  use ExUnit.Case, async: false
  import TestUtils
  alias FDB.Directory.HighContentionAllocator
  alias FDB.Directory
  alias FDB.Database
  use ExUnitProperties
  alias FDB.Coder.{Identity, Subspace, ByteString, Integer, Tuple, LittleEndianInteger}
  alias FDB.KeySelectorRange
  alias FDB.KeySelector
  alias FDB.Transaction
  require Logger

  setup do
    flushdb()
  end

  property "unique" do
    check all count <- integer(1..1500),
              concurrency <- integer(1..100),
              max_run_time: 3000,
              max_shrinking_steps: 0 do
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

      key =
        Subspace.concat(
          Subspace.new(<<0xFE>>),
          Subspace.new(<<0xFE>>, Identity.new(), ByteString.new())
        )
        |> Subspace.concat(
          Subspace.new("hca", Tuple.new({Integer.new(), Integer.new()}), ByteString.new())
        )

      count_coder =
        Transaction.Coder.new(
          key,
          LittleEndianInteger.new(64)
        )

      candidate_coder =
        Transaction.Coder.new(
          key,
          Identity.new()
        )

      Database.transact(database, fn t ->
        {{0, start}, report_size} =
          Transaction.get_range(t, KeySelectorRange.starts_with({0}), %{
            coder: count_coder
          })
          |> Enum.to_list()
          |> List.last()

        allocated =
          Transaction.get_range(
            t,
            KeySelectorRange.range(
              KeySelector.first_greater_or_equal({1, start}),
              KeySelector.first_greater_or_equal({1}, %{prefix: :last})
            ),
            %{
              coder: candidate_coder
            }
          )
          |> Enum.count()

        Logger.info(inspect(%{start: start, allocated: allocated, report_size: report_size}))

        assert allocated <= report_size
      end)
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

      bharat = Directory.create_or_open(root, tr, ["bharat"])
      _bihar = Directory.create(bharat, tr, ["bihar"])
      india = Directory.move_to(bharat, tr, ["india"])
      assert Directory.list(india, tr) == ["bihar"]
    end)
  end
end
