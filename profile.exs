import ExProf.Macro
alias FDB.Database
alias FDB.Transaction

values =
  Enum.map(0..1000, fn _ -> :crypto.strong_rand_bytes(Enum.random(8..100)) end) |> List.to_tuple()

keys = Enum.map(0..1000, fn _ -> "fdb:" <> :crypto.strong_rand_bytes(12) end) |> List.to_tuple()

:ok = FDB.start()

db =
  FDB.Cluster.create()
  |> Database.create()

profile do
  Enum.each(0..1000, fn i ->
    :ok =
      Database.transact(db, fn t ->
        Transaction.set(t, elem(keys, i), elem(values, i))
      end)

    Database.transact(db, fn t ->
      Transaction.get(t, elem(keys, i))
    end)

    :ok
  end)
end
