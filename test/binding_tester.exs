defmodule FDB.BindingTester do
  alias FDB.Transaction
  alias FDB.KeySelector
  alias FDB.Coder.{Subspace, Identity, UnicodeString, Tuple, Integer, Dynamic}

  def run(prefix, version, cluster) do
    :ok = FDB.Network.start(version)

    coder = %Transaction.Coder{
      key: Subspace.new(<<0x01>> <> prefix <> <<0x00>>, FDB.Coder.Integer.new()),
      value: Dynamic.new()
    }

    db = FDB.Cluster.create(cluster)
    |> FDB.Database.create(coder)

    IO.inspect({prefix, version, cluster})

    Transaction.get_range_stream(
      db,
      KeySelector.first_greater_than(nil),
      KeySelector.last_less_than(nil)
    )
    |> Stream.each(fn {key, value} ->
      IO.inspect({key, value})
    end)
    |> Stream.run

    IO.inspect("done")
  end
end

args = System.argv
FDB.BindingTester.run(Enum.at(args, 0), String.to_integer(Enum.at(args, 1)), Enum.at(args, 2))
