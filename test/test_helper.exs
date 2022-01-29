:ok = FDB.start()
ExUnit.start(exclude: [:integration], capture_log: true)

System.at_exit(fn _exit_code ->
  :ok = FDB.Network.stop()
end)

defmodule TestUtils do
  alias FDB.Database
  alias FDB.Transaction
  alias FDB.KeyRange
  alias FDB.Transaction.Coder
  alias FDB.Future

  require ExUnit.Assertions
  import ExUnit.Assertions

  def flushdb do
    t = new_transaction()

    :ok =
      Transaction.clear_range(
        t,
        KeyRange.range("", <<0xFF>>)
      )

    Transaction.commit(t)
  end

  def random_value(size \\ 1024) do
    :crypto.strong_rand_bytes(size)
  end

  def random_key(size \\ 1024) do
    "fdb:" <> :crypto.strong_rand_bytes(size)
  end

  def new_transaction do
    Database.create()
    |> Transaction.create()
  end

  def new_database do
    Database.create()
  end

  def sort_order(value) do
    Enum.with_index(value)
    |> Enum.sort_by(fn {value, _index} -> value end)
    |> Enum.map(fn {_value, index} -> index end)
  end

  def assert_coder_order_symmetry(coder, values, opts \\ []) do
    sorted = Keyword.get(opts, :sorted, true)
    coder = Transaction.Coder.new(coder)

    encoded =
      Enum.map(values, fn binary ->
        Coder.encode_key(coder, binary)
      end)

    decoded =
      Enum.map(encoded, fn key ->
        Coder.decode_key(coder, key)
      end)

    assert values == decoded

    if sorted && !nested_any?(values, fn value -> value == 0.0 end) do
      assert sort_order(values) == sort_order(encoded)
    end
  end

  defp nested_any?(values, cb) when is_tuple(values) do
    Tuple.to_list(values)
    |> nested_any?(cb)
  end

  defp nested_any?(values, cb) when is_map(values) do
    Map.to_list(values)
    |> nested_any?(cb)
  end

  defp nested_any?(values, cb) when is_list(values) do
    Enum.any?(values, fn value -> nested_any?(value, cb) end)
  end

  defp nested_any?(value, cb) do
    cb.(value)
  end

  defmacro fuzz(module, method, arity, generator, options \\ Macro.escape(%{})) do
    module = Macro.expand(module, __CALLER__)
    name = "#{module}.#{method}/#{arity}"

    quote do
      property unquote(name) do
        check all arguments <- unquote(generator) do
          try do
            result = apply(unquote(module), unquote(method), arguments)

            cond do
              Map.get(unquote(options), :stream) -> Stream.run(result)
              Map.get(unquote(options), :future) -> Future.await(result)
              true -> :ok
            end
          rescue
            e in [FDB.Error, ArgumentError, FunctionClauseError, KeyError] ->
              :ok

            e in [ErlangError] ->
              unless Map.has_key?(e, :original) do
                reraise e, System.stacktrace()
              end

              :ok
          end
        end
      end
    end
  end
end
