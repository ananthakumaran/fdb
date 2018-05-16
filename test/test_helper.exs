:ok = FDB.start()
ExUnit.start()

System.at_exit(fn _exit_code ->
  :ok = FDB.stop()
end)
