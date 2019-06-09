alias FDB.Database
alias FDB.Transaction
alias FDB.KeyRange

File.write!("result.ndjson", "", [:write])

defmodule Benchee.Formatters.FDB do
  use Benchee.Formatter

  def format(suite) do
    concurrency = suite.configuration.parallel

    Enum.map(suite.scenarios, fn s ->
      stats = s.run_time_statistics

      ops_scale =
        cond do
          s.job_name =~ "10 op" -> 10 * concurrency
          true -> concurrency
        end

      %{
        name: s.job_name,
        concurrency: concurrency,
        ops: ops_scale * stats.ips,
        average: stats.average / 1000,
        max: stats.maximum / 1000,
        min: stats.minimum / 1000,
        deviation: stats.std_dev_ratio * 100
      }
    end)
  end

  def write(scenarios) do
    pattern = "~*s~*s~*s~*s~*s~*s~*s\n"
    widths = [15, 15, 10, 13, 10, 10, 12]

    format(pattern, widths, [
      "name",
      "concurrency",
      "ops/s",
      "average ms",
      "max ms",
      "min ms",
      "deviation"
    ])

    Enum.each(scenarios, fn s ->
      File.write!("result.ndjson", [Jason.encode!(s), "\n"], [:append])

      format(pattern, widths, [
        s.name,
        to_string(s.concurrency),
        to_string(trunc(s.ops)),
        Float.to_string(Float.round(s.average, 3)),
        Float.to_string(Float.round(s.max, 3)),
        Float.to_string(Float.round(s.min, 3)),
        to_charlist(" ±" <> Float.to_string(Float.round(s.deviation, 2)) <> "%")
      ])
    end)
  end

  defp format(pattern, widths, values) do
    args =
      Enum.with_index(values)
      |> Enum.map(fn {value, i} ->
        [Enum.at(widths, i), value]
      end)
      |> Enum.concat()

    :io.fwrite(pattern, args)
  end
end

defmodule Utils do
  @key_size 0..100_000
  @keys Enum.map(@key_size, fn _ -> "fdb:" <> :crypto.strong_rand_bytes(12) end)
        |> List.to_tuple()

  @value_size 0..10000
  @values Enum.map(@value_size, fn _ -> :crypto.strong_rand_bytes(Enum.random(8..100)) end)
          |> List.to_tuple()

  def random_value do
    elem(@values, Enum.random(@value_size))
  end

  def random_key do
    elem(@keys, Enum.random(@key_size))
  end
end

:ok = FDB.start()

db = Database.create()

Database.transact(db, fn t ->
  :ok =
    Transaction.clear_range(
      t,
      KeyRange.range("", <<0xFF>>)
    )
end)

runs = [1, 5, 10, 20, 40, 60, 80, 100]

Enum.each(runs, fn concurrency ->
  Benchee.run(
    %{
      "read   1 op" => fn ->
        Database.transact(db, fn t ->
          Transaction.get(t, Utils.random_key())
        end)
      end,
      "write  1 op" => fn ->
        Database.transact(db, fn t ->
          Transaction.set(t, Utils.random_key(), Utils.random_value())
        end)
      end,
      "read  10 op" => fn ->
        Database.transact(db, fn t ->
          for _ <- 1..10 do
            Transaction.get(t, Utils.random_key())
          end
        end)
      end,
      "write 10 op" => fn ->
        Database.transact(db, fn t ->
          for _ <- 1..10 do
            Transaction.set(t, Utils.random_key(), Utils.random_value())
          end
        end)
      end
    },
    parallel: concurrency,
    formatters: [Benchee.Formatters.FDB]
  )
end)
