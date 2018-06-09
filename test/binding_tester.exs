defmodule FDB.TransactionMap do
  use Agent

  def start_link do
    Agent.start_link(fn -> Map.new() end, name: __MODULE__)
  end

  def put(name, transaction) do
    Agent.update(__MODULE__, &Map.put(&1, name, transaction))
  end

  def get(name) do
    Agent.get(__MODULE__, &Map.fetch!(&1, name))
  end
end

defmodule Stack do
  def push(stack, value, id) do
    [{value, id} | stack]
  end

  def pop(stack, count \\ 1) do
    {values, stack} = Enum.split(stack, count)

    List.to_tuple(Enum.map(values, &elem(&1, 0)))
    |> Tuple.append(stack)
  end

  def split(stack, count \\ 1) do
    {values, stack} = Enum.split(stack, count)
    {Enum.map(values, &elem(&1, 0)), stack}
  end
end

defmodule FDB.Machine do
  alias FDB.Transaction
  alias FDB.Database
  alias FDB.Future
  alias FDB.TransactionMap
  alias FDB.Coder.Dynamic
  alias FDB.Coder
  alias FDB.KeySelector
  alias FDB.Option
  import Stack

  defmodule State do
    defstruct stack: [], db: nil, prefix: nil, transaction_name: nil, last_version: nil
  end

  def init(db, prefix) do
    db =
      FDB.Database.set_coder(
        db,
        %FDB.Transaction.Coder{key: Dynamic.new(), value: Dynamic.new()}
      )

    %State{db: db, prefix: prefix, transaction_name: prefix}
  end

  def execute({id, instruction}, s) do
    [{:unicode_string, op} | rest] = Tuple.to_list(instruction)

    IO.puts(
      "#{String.pad_leading(to_string(id), 5)} #{String.pad_leading(op, 20)} #{inspect(rest)}"
    )

    cond do
      String.ends_with?(op, "_DATABASE") ->
        op = String.replace(op, "_DATABASE", "")
        old_t = trx(s)
        t = Transaction.create(s.db)
        :ok = TransactionMap.put(s.transaction_name, t)
        s = do_execute(id, List.to_tuple([op | rest]), s)
        :ok = TransactionMap.put(s.transaction_name, old_t)

        [top | rest] = s.stack

        case top do
          {_, ^id} ->
            s

          _ ->
            f = Transaction.commit_q(t)
            %{s | stack: push(s.stack, f, id)}
        end

      true ->
        do_execute(id, List.to_tuple([op | rest]), s)
    end
  end

  def do_execute(id, {"PUSH", value}, s) do
    %{s | stack: push(s.stack, value, id)}
  end

  def do_execute(id, {"SUB"}, s) do
    {{_, a}, {_, b}, stack} = pop(s.stack, 2)
    %{s | stack: push(stack, {:arbitrary_integer, a - b}, id)}
  end

  def do_execute(id, {"SWAP"}, s) do
    {{_, i}, stack} = pop(s.stack)

    stack =
      List.replace_at(stack, i, List.first(stack))
      |> List.replace_at(0, Enum.at(stack, i))

    %{s | stack: stack}
  end

  def do_execute(id, {"TUPLE_PACK"}, s) do
    {{_, i}, stack} = pop(s.stack)
    {items, stack} = split(stack, i)
    %{s | stack: push(stack, tuple_pack(items), id)}
  end

  def do_execute(id, {"TUPLE_SORT"}, s) do
    {{_, i}, stack} = pop(s.stack)
    {items, stack} = split(stack, i)
    %{s | stack: push(stack, tuple_sort(items), id)}
  end

  def do_execute(id, {"TUPLE_RANGE"}, s) do
    {{_, i}, stack} = pop(s.stack)
    {items, stack} = split(stack, i)
    IO.inspect(items, label: "tuple")
    {start_key, end_key} = tuple_range(items)

    stack =
      push(stack, start_key, id)
      |> push(end_key, id)

    %{s | stack: stack}
  end

  def do_execute(id, {"ENCODE_DOUBLE"}, s) do
    {{_, <<n::64-float-big>>}, stack} = pop(s.stack)
    %{s | stack: push(stack, {:float64, n}, id)}
  end

  def do_execute(id, {op}, s) when op in ["NEW_TRANSACTION", "RESET"] do
    db = Database.set_coder(s.db, %Transaction.Coder{})
    :ok = TransactionMap.put(s.transaction_name, Transaction.create(db))
    s
  end

  def do_execute(id, {"LOG_STACK"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    db =
      Database.set_coder(s.db, %Transaction.Coder{
        key: Coder.Tuple.new({Coder.Identity.new(), Coder.Integer.new(), Coder.Integer.new()}),
        value: Coder.Dynamic.new()
      })

    Transaction.transact(db, fn t ->
      Enum.reverse(stack)
      |> Enum.with_index()
      |> Enum.each(fn {{item, id}, i} ->
        item =
          cond do
            is_binary(item) -> {:byte_string, item}
            true -> item
          end

        Transaction.set(t, {prefix, i, id}, item)
      end)
    end)

    %{s | stack: []}
  end

  def do_execute(id, {"GET_READ_VERSION"}, s) do
    %{
      s
      | last_version: Transaction.get_read_version(trx(s)),
        stack: push(s.stack, "GOT_READ_VERSION", id)
    }
  end

  def do_execute(id, {"GET_KEY"}, s) do
    {{:byte_string, key}, {:integer, or_equal}, {:integer, offset}, {:byte_string, prefix}, stack} =
      pop(s.stack, 4)

    result =
      Transaction.get_key(
        trx(s, %Transaction.Coder{}),
        {key, or_equal, offset}
      )

    result =
      cond do
        String.starts_with?(result, prefix) -> result
        result < prefix -> prefix
        true -> strinc(result)
      end

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"GET_RANGE_STARTS_WITH"}, s) do
    {{:byte_string, prefix}, {:integer, limit}, {:integer, reverse}, {:integer, streaming_mode},
     stack} = pop(s.stack, 4)

    result =
      rescue_error(fn ->
        Transaction.get_range_stream(
          trx(s, %Transaction.Coder{}),
          KeySelector.first_greater_or_equal(prefix),
          KeySelector.first_greater_or_equal(prefix),
          %{
            limit: limit,
            reverse: reverse,
            mode: streaming_mode
          }
        )
        |> Enum.map(&Tuple.to_list/1)
        |> Enum.concat()
        |> tuple_pack()
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"SET"}, s) do
    {{:byte_string, key}, {:byte_string, value}, stack} = pop(s.stack, 2)
    :ok = Transaction.set(trx(s, %Transaction.Coder{}), key, value)
    %{s | stack: stack}
  end

  def do_execute(id, {"ATOMIC_OP"}, s) do
    {{:unicode_string, op_name}, {:byte_string, key}, {:byte_string, value}, stack} =
      pop(s.stack, 3)

    op = apply(Option, String.to_atom("mutation_type_" <> String.downcase(op_name)), [])
    :ok = Transaction.atomic_op(trx(s, %Transaction.Coder{}), key, value, op)
    %{s | stack: stack}
  end

  def do_execute(id, {"DISABLE_WRITE_CONFLICT"}, s) do
    :ok =
      Transaction.set_option(
        trx(s),
        Option.transaction_option_next_write_no_write_conflict_range()
      )

    s
  end

  def do_execute(id, {"WRITE_CONFLICT_RANGE"}, s) do
    {begin_key, end_key, stack} = pop(s.stack, 2)

    result =
      rescue_error(fn ->
        Transaction.add_conflict_range(
          trx(s, s.db.coder),
          begin_key,
          end_key,
          Option.conflict_range_type_write()
        )

        "SET_CONFLICT_RANGE"
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"READ_CONFLICT_KEY"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)

    result =
      rescue_error(fn ->
        Transaction.add_conflict_range(
          trx(s, %Transaction.Coder{}),
          key,
          key,
          Option.conflict_range_type_read()
        )

        "SET_CONFLICT_KEY"
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"CLEAR"}, s) do
    {key, stack} = pop(s.stack)
    :ok = Transaction.clear(trx(s, s.db.coder), key)
    %{s | stack: stack}
  end

  def do_execute(id, {"CLEAR_RANGE"}, s) do
    {{:byte_string, start_key}, {:byte_string, end_key}, stack} = pop(s.stack, 2)
    :ok = Transaction.clear_range(trx(s, %Transaction.Coder{}), start_key, end_key)
    %{s | stack: stack}
  end

  def do_execute(id, {"CLEAR_RANGE_STARTS_WITH"}, s) do
    {key, stack} = pop(s.stack)
    :ok = Transaction.clear_range(trx(s, s.db.coder), key, key)
    %{s | stack: stack}
  end

  def do_execute(id, {"COMMIT"}, s) do
    %{s | stack: push(s.stack, Transaction.commit_q(trx(s)), id)}
  end

  def do_execute(id, {"WAIT_FUTURE"}, s) do
    [{f, id} | stack] = s.stack

    stack =
      if is_reference(f) do
        result = Future.resolve(f)

        cond do
          result in [:ok, nil] -> push(stack, "RESULT_NOT_PRESENT", id)
          true -> push(stack, result, id)
        end
      else
        push(stack, f, id)
      end

    %{s | stack: stack}
  end

  def do_execute(id, instruction, _s) do
    raise "Unknown instruction #{inspect(instruction)}"
  end

  defp tuple_pack(items) do
    coder = Dynamic.new()
    value = coder.module.encode(List.to_tuple(items), coder.opts)
  end

  defp tuple_unpack({:byte_string, binary}) do
    coder = Dynamic.new()
    {value, ""} = coder.module.decode(binary, coder.opts)
    value
  end

  defp tuple_sort(items) do
    coder = Dynamic.new()

    Enum.map(items, fn item ->
      {value, ""} = coder.module.decode(item, coder.opts)
      value
    end)
    |> Enum.sort_by(fn item -> coder.module.encode(item, coder.opts) end)
    |> tuple_pack()
  end

  defp tuple_range(items) do
    coder = Dynamic.new()
    coder.module.range(List.to_tuple(items), coder.opts)
  end

  defp strinc(text) do
    text = String.replace(text, ~r/#{<<0xFF>>}*\z/, "")
    {prefix, <<last::integer>>} = String.split_at(text, -1)
    prefix <> <<last + 1::integer>>
  end

  defp trx(s, coder \\ nil) do
    t = FDB.TransactionMap.get(s.transaction_name)

    if coder do
      Transaction.set_coder(t, coder)
    else
      t
    end
  end

  defp rescue_error(cb) do
    cb.()
  rescue
    e in FDB.Error ->
      tuple_pack([{:byte_string, "ERROR"}, {:byte_string, Integer.to_string(e.code)}])
  end
end

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

    {:ok, _pid} = FDB.TransactionMap.start_link()

    db =
      FDB.Cluster.create(cluster)
      |> FDB.Database.create(coder)

    Transaction.get_range_stream(
      db,
      KeySelector.first_greater_than(nil),
      KeySelector.last_less_than(nil)
    )
    |> Enum.reduce(FDB.Machine.init(db, prefix), &FDB.Machine.execute/2)
  end
end

args = System.argv()
FDB.BindingTester.run(Enum.at(args, 0), String.to_integer(Enum.at(args, 1)), Enum.at(args, 2))
