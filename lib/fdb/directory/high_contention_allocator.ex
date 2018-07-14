defmodule FDB.Directory.HighContentionAllocator do
  alias FDB.Coder.{Integer, ByteString}
  alias FDB.Transaction
  alias FDB.KeySelectorRange
  alias FDB.KeyRange
  alias FDB.Option

  @counter 0
  @recent 1

  def allocate(directory, t) do
    integer = Integer.new()
    t = Transaction.set_coder(t, directory.hca_coder)
    candidate = search(t)
    integer.module.encode(candidate, integer.opts)
  end

  defp search(t) do
    result =
      Transaction.get_range(t, KeySelectorRange.starts_with({@counter}), %{
        limit: 1,
        reverse: true,
        snapshot: true
      })
      |> Enum.to_list()

    start =
      case result do
        [] -> 0
        [{{@counter, start}, _}] -> start
      end

    candidate_range = range(t, start, false)

    case search_candidate(t, candidate_range) do
      nil -> search(t)
      candidate -> candidate
    end
  end

  defp range(t, start, window_advanced) do
    if window_advanced do
      :ok =
        Transaction.clear_range(
          t,
          KeyRange.range({@counter}, {@counter, start}, %{begin_key_prefix: :first})
        )

      :ok =
        Transaction.set_option(t, Option.transaction_option_next_write_no_write_conflict_range())

      :ok =
        Transaction.clear_range(
          t,
          KeyRange.range({@recent}, {@recent, start}, %{begin_key_prefix: :first})
        )
    end

    :ok = Transaction.atomic_op(t, {@counter, start}, Option.mutation_type_add(), 1)

    count =
      case Transaction.get(t, {@counter, start}, %{snapshot: true}) do
        nil -> 0
        n -> n
      end

    window = window_size(start)

    if count * 2 < window do
      start..(start + window)
    else
      range(t, start + window, true)
    end
  end

  defp window_size(start) do
    cond do
      start < 255 -> 64
      start < 65535 -> 1024
      true -> 8192
    end
  end

  defp search_candidate(t, search_range) do
    candidate = Enum.random(search_range)

    latest_start =
      Transaction.get_range(t, KeySelectorRange.starts_with({@counter}), %{
        limit: 1,
        reverse: true,
        snapshot: true
      })
      |> Enum.map(fn {{@counter, start}, _} -> start end)
      |> List.first()

    t1 =
      Transaction.set_coder(
        t,
        Transaction.Coder.new(
          t.coder.key,
          ByteString.new()
        )
      )

    candidate_value = Transaction.get(t1, {@recent, candidate})

    :ok =
      Transaction.set_option(t1, Option.transaction_option_next_write_no_write_conflict_range())

    :ok = Transaction.set(t1, {@recent, candidate}, "")

    cond do
      latest_start && latest_start > search_range.first ->
        nil

      is_nil(candidate_value) ->
        :ok =
          Transaction.add_conflict_key(
            t,
            {@recent, candidate},
            Option.conflict_range_type_write()
          )

        candidate

      true ->
        search_candidate(t, search_range)
    end
  end
end
