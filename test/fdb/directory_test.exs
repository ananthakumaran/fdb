defmodule FDB.DirectoryTest do
  use ExUnit.Case, async: false
  import TestUtils
  alias FDB.Directory.HighContentionAllocator
  alias FDB.Directory
  alias FDB.Database
  use ExUnitProperties
  alias FDB.Coder.{Identity, Subspace, ByteString, Integer, Tuple, LittleEndianInteger, Dynamic}
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

      assert_uniqueness(dirs)

      key =
        Subspace.concat(
          Subspace.new(<<0xFE>>),
          Subspace.new({<<0xFE>>, ByteString.new()}, Identity.new())
        )
        |> Subspace.concat(
          Subspace.new({"hca", ByteString.new()}, Tuple.new({Integer.new(), Integer.new()}))
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

  test "same transaction" do
    database = new_database()
    root = Directory.new()

    dirs =
      Task.async_stream(
        1..50,
        fn _ ->
          Database.transact(database, fn t ->
            Task.async_stream(
              1..5,
              fn _ ->
                HighContentionAllocator.allocate(
                  root,
                  t
                )
              end,
              max_concurrency: 5
            )
            |> Enum.map(fn {:ok, dir} -> dir end)
          end)
        end,
        max_concurrency: 5
      )
      |> Enum.map(fn {:ok, dirs} -> dirs end)
      |> Enum.concat()

    assert_uniqueness(dirs)
  end

  test "create" do
    database = new_database()
    root = Directory.new()

    Database.transact(database, fn tr ->
      usa = Directory.create(root, tr, ["usa"])
      assert Directory.list(root, tr) == ["usa"]
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

    Database.transact(database, fn tr ->
      refute Directory.exists?(root, tr, ["bharat"])
      assert Directory.exists?(root, tr, ["india"])
      india = Directory.open(root, tr, ["india"])
      Directory.remove(india, tr)
      refute Directory.exists?(root, tr, ["india"])
    end)
  end

  test "manual prefix" do
    database = new_database()
    root = Directory.new()

    Database.transact(database, fn tr ->
      assert_raise(ArgumentError, fn -> Directory.create(root, tr, ["a"], %{prefix: "a"}) end)
    end)

    root = Directory.new(%{allow_manual_prefixes: true})

    Database.transact(database, fn tr ->
      Directory.create(root, tr, ["a"], %{prefix: "abcde"})
      assert_raise(ArgumentError, fn -> Directory.create(root, tr, ["b"], %{prefix: "abcde"}) end)
      assert_raise(ArgumentError, fn -> Directory.create(root, tr, ["c"], %{prefix: "a"}) end)
    end)
  end

  test "move" do
    database = new_database()
    root = Directory.new()

    Database.transact(database, fn tr ->
      default = Directory.create(root, tr, ["default1"])
      Directory.create(default, tr, ["1"])
      Directory.create(root, tr, ["1"])
      Directory.move_to(default, tr, ["1", "1"])

      assert Directory.list(root, tr, ["1"]) == ["1"]
    end)

    Database.transact(database, fn tr ->
      Directory.create(root, tr, ["2", "2"])
      d2 = Directory.create(root, tr, ["default1", "3"])
      Directory.move_to(d2, tr, ["2", "2", "2"])
    end)
  end

  test "partition" do
    database = new_database()
    root = Directory.new()

    Database.transact(database, fn tr ->
      usa = Directory.create(root, tr, ["usa"])
      p1 = Directory.create_or_open(root, tr, ["p1"], %{layer: "partition"})
      _p1_1 = Directory.create(p1, tr, ["1"])
      _p1_2 = Directory.create(p1, tr, ["2"])
      _p1_2 = Directory.create(p1, tr, ["2", "2", "2"])
      p1_3 = Directory.create(p1, tr, ["3"])
      assert p1_3.path == ["p1", "3"]
      assert Directory.list(p1, tr) == ["1", "2", "3"]
      assert Directory.list(root, tr, ["p1"]) == ["1", "2", "3"]

      p1_3_a = Directory.create(p1_3, tr, ["a"])
      assert p1_3_a.path == ["p1", "3", "a"]
      p1_4 = Directory.move_to(p1_3, tr, ["p1", "4"])
      assert Directory.list(p1_4, tr) == ["a"]
      assert Directory.list(root, tr, ["p1", "4"]) == ["a"]

      assert_raise(ArgumentError, fn -> Directory.move_to(usa, tr, ["p1", "6"]) end)

      Directory.remove(p1, tr, ["4"])
    end)
  end

  def debug() do
    database = new_database()

    prefix_coder =
      Transaction.Coder.new(
        Subspace.new(<<254>>, Dynamic.new()),
        Identity.new()
      )

    Database.transact(database, fn tr ->
      Transaction.get_range(tr, KeySelectorRange.starts_with({}), %{coder: prefix_coder})
      |> Enum.to_list()
      |> IO.inspect()
    end)
  end

  def assert_uniqueness(dirs) do
    assert length(dirs) == length(Enum.uniq(dirs))

    for x <- dirs, y <- dirs, x != y do
      size = Enum.min([byte_size(x), byte_size(y)])
      assert :binary.longest_common_prefix([x, y]) < size, "invalid #{inspect(x)} #{inspect(y)}"
    end
  end
end
