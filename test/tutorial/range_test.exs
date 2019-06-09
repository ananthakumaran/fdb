defmodule FDB.Tutorial.RangeTest do
  use ExUnit.Case, async: false
  alias FDB.{Transaction, Database, KeySelector, KeySelectorRange}
  alias FDB.Coder.{Integer, Tuple, ByteString, Subspace}
  alias FDB.Directory
  use Timex
  import TestUtils

  setup do
    flushdb()
  end

  test "range" do
    db = Database.create()

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
            # month
            ByteString.new(),
            # day
            Integer.new()
          })
        ),
        Integer.new()
      )

    db = Database.set_defaults(db, %{coder: coder})
    populate(db)

    assert_range(
      db,
      KeySelectorRange.starts_with({"July"}),
      month_range("July", 1..31)
    )

    assert_range(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_or_equal({"July"}, %{prefix: :first}),
        KeySelector.first_greater_or_equal({"July"}, %{prefix: :last})
      ),
      month_range("July", 1..31)
    )

    assert_range(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_than({"July", 10}),
        KeySelector.first_greater_or_equal({"July"}, %{prefix: :last})
      ),
      month_range("July", 11..31)
    )

    assert_range(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_or_equal({"July", 10}),
        KeySelector.first_greater_or_equal({"July"}, %{prefix: :last})
      ),
      month_range("July", 10..31)
    )

    assert_range(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_than({"July", 10}),
        KeySelector.first_greater_than({"July", 15})
      ),
      month_range("July", 11..15)
    )

    assert_range(
      db,
      KeySelectorRange.range(
        KeySelector.first_greater_or_equal({"July"}, %{prefix: :first}),
        KeySelector.first_greater_than({"July", 15})
      ),
      month_range("July", 1..15)
    )
  end

  def populate(db) do
    Interval.new(from: ~D[2018-01-01], until: [months: 12], right_open: true)
    |> Interval.with_step(days: 1)
    |> Task.async_stream(
      fn time ->
        month = Timex.month_name(time.month)

        Database.transact(db, fn t ->
          Transaction.set(t, {month, time.day}, 1)
        end)
      end,
      max_concurrency: 100
    )
    |> Stream.run()
  end

  def month_range(name, range) do
    Enum.map(range, fn x ->
      {name, x}
    end)
  end

  def assert_range(db, range, expected) do
    result =
      Database.get_range_stream(db, range)
      |> Enum.map(fn {key, _} ->
        key
      end)

    assert result == expected
  end
end
