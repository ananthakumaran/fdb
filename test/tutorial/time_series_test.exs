defmodule FDB.Tutorial.TimeSeriesTest do
  use ExUnit.Case, async: false
  alias FDB.{Transaction, Database, Cluster, KeySelector, KeySelectorRange}
  alias FDB.Coder.{Integer, Tuple, NestedTuple, ByteString, Subspace}
  alias FDB.Directory
  use Timex
  import TestUtils
  use FDB.Future.Operators

  setup do
    flushdb()
  end

  test "timeseries" do
    db =
      Cluster.create()
      |> Database.create()

    ts_dir =
      Database.transact(db, fn tr ->
        root = Directory.new()
        Directory.create(root, tr, ["ts"])
      end)

    coder =
      Transaction.Coder.new(
        Subspace.new(
          ts_dir,
          Tuple.new({
            # date
            NestedTuple.new({
              NestedTuple.new({Integer.new(), Integer.new(), Integer.new()}),
              NestedTuple.new({Integer.new(), Integer.new(), Integer.new()})
            }),
            # website
            ByteString.new(),
            # page
            ByteString.new(),
            # browser
            ByteString.new()
          })
        ),
        Integer.new()
      )

    db = Database.set_defaults(db, %{coder: coder})
    populate(db)

    Database.transact(db, fn t ->
      m = Transaction.get_q(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "mozilla"})
      c = Transaction.get_q(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "chrome"})
      assert 2 == @m + @c

      assert nil ==
               Transaction.get(
                 t,
                 {{{2017, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "chrome"}
               )
    end)

    assert_range_size(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_than({{{2018, 03, 01}, {0, 0, 0}}}, %{prefix: :first}),
        KeySelector.first_greater_or_equal({{{2018, 03, 31}, {23, 0, 0}}}, %{prefix: :last})
      ),
      31 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_than({{{2018, 03, 01}, {0, 0, 0}}}, %{prefix: :first}),
        KeySelector.first_greater_or_equal({{{2018, 04, 01}, {0, 0, 0}}}, %{prefix: :first})
      ),
      31 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03, 01}, {0, 0, 0}}}),
      4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03, 01}, {0, 0}}}),
      4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03, 01}, {0}}}),
      4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03, 01}, {}}}),
      24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03, 01}}}),
      1 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018, 03}}}),
      31 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{2018}}}),
      61 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{{}}}),
      61 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({{}}),
      61 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with({}),
      61 * 24 * 4
    )

    assert_range_size(
      db,
      KeySelectorRange.starts_with(nil),
      61 * 24 * 4
    )
  end

  def populate(db) do
    Interval.new(from: ~D[2018-03-01], until: [months: 2], right_open: true)
    |> Interval.with_step(hours: 1)
    |> Task.async_stream(
      fn time ->
        time = NaiveDateTime.to_erl(time)

        Database.transact(db, fn t ->
          Transaction.set(t, {time, "www.ananthakumaran.in", "/books", "mozilla"}, 1)
          Transaction.set(t, {time, "www.ananthakumaran.in", "/books", "chrome"}, 1)
          Transaction.set(t, {time, "www.github.com", "/fdb", "mozilla"}, 1)
          Transaction.set(t, {time, "www.github.com", "/fdb", "chrome"}, 1)
        end)
      end,
      max_concurrency: 100
    )
    |> Stream.run()
  end

  def assert_range_size(db, range, size) do
    result =
      Database.get_range(db, range)
      |> Enum.to_list()

    assert length(result) == size
  end
end
