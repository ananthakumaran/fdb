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

defmodule FDB.Machine do
  alias FDB.Transaction
  alias FDB.Future
  alias FDB.TransactionMap
  alias FDB.Coder.Dynamic
  alias FDB.KeySelector
  alias FDB.Option

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

  def execute({id, {{_, "PUSH"}, value}}, s) do
    %{s | stack: [value | s.stack]}
  end

  def execute({id, {{_, "SUB"}}}, s) do
    [{_, a} | [{_, b} | stack]] = s.stack
    %{s | stack: [{:arbitrary_integer, a - b} | stack]}
  end

  def execute({id, {{_, "SWAP"}}}, s) do
    [{_, i} | stack] = s.stack

    stack =
      List.replace_at(stack, i, List.first(stack))
      |> List.replace_at(0, Enum.at(stack, i))

    %{s | stack: stack}
  end

  def execute({id, {{_, "TUPLE_PACK"}}}, s) do
    [{_, i} | stack] = s.stack
    {items, stack} = Enum.split(stack, i)
    %{s | stack: [tuple_pack(items) | stack]}
  end

  def execute({id, {{_, "TUPLE_SORT"}}}, s) do
    [{_, i} | stack] = s.stack
    {items, stack} = Enum.split(stack, i)
    %{s | stack: [tuple_sort(items) | stack]}
  end

  def execute({id, {{_, op}}}, s) when op in ["NEW_TRANSACTION", "RESET"] do
    :ok = TransactionMap.put(s.transaction_name, Transaction.create(s.db))
    s
  end

  def execute({id, {{_, "GET_READ_VERSION"}}}, s) do
    %{
      s
      | last_version: Transaction.get_read_version(trx(s)),
        stack: [{:byte_string, "GOT_READ_VERSION"} | s.stack]
    }
  end

  def execute({id, {{_, "GET_RANGE_STARTS_WITH"}}}, s) do
    {[prefix, {:integer, limit}, {:integer, reverse}, {:integer, streaming_mode}], stack} =
      Enum.split(s.stack, 4)

    result =
      Transaction.get_range_stream(
        trx(s),
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

    %{s | stack: [tuple_pack(result) | stack]}
  end

  def execute({id, {{_, "SET"}}}, s) do
    [key | [value | stack]] = s.stack
    :ok = Transaction.set(trx(s), key, value)
    %{s | stack: stack}
  end

  def execute({id, {{_, "DISABLE_WRITE_CONFLICT"}}}, s) do
    :ok =
      Transaction.set_option(
        trx(s),
        Option.transaction_option_next_write_no_write_conflict_range()
      )

    s
  end

  def execute({id, {{_, "WRITE_CONFLICT_RANGE"}}}, s) do
    [begin_key | [end_key | stack]] = s.stack

    result =
      rescue_error(fn ->
        Transaction.add_conflict_range(
          trx(s),
          begin_key,
          end_key,
          Option.conflict_range_type_write()
        )
      end)

    %{s | stack: [result | stack]}
  end

  def execute({id, {{_, "CLEAR_DATABASE"}}}, s) do
    [key | stack] = s.stack

    t = Transaction.create(s.db)
    :ok = Transaction.clear(t, key)
    f = Transaction.commit_q(t)

    %{s | stack: [f | stack]}
  end

  def execute({id, {{_, "CLEAR_RANGE_STARTS_WITH_DATABASE"}}}, s) do
    [key | stack] = s.stack

    t = Transaction.create(s.db)
    :ok = Transaction.clear_range(t, key, key)
    f = Transaction.commit_q(t)

    %{s | stack: [f | stack]}
  end

  def execute({id, {{_, "COMMIT"}}}, s) do
    %{s | stack: [Transaction.commit_q(trx(s)) | s.stack]}
  end

  def execute({id, {{_, "WAIT_FUTURE"}}}, s) do
    [f | stack] = s.stack
    %{s | stack: [Future.resolve(f) | stack]}
  end

  def execute({id, instruction}, _) do
    raise "Unknown instruction #{inspect(instruction)}"
  end

  defp tuple_pack(items) do
    coder = Dynamic.new()
    value = coder.module.encode(List.to_tuple(items), coder.opts)
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

  defp trx(s) do
    FDB.TransactionMap.get(s.transaction_name)
  end

  defp rescue_error(cb) do
    cb.()
  rescue
    e in FDB.Error ->
      {{:byte_string, "ERROR"}, {:byte_string, Integer.to_string(e.code)}}
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

    IO.inspect({prefix, version, cluster})

    Transaction.get_range_stream(
      db,
      KeySelector.first_greater_than(nil),
      KeySelector.last_less_than(nil)
    )
    |> Stream.each(fn {key, value} ->
      IO.inspect({key, value})
    end)
    |> Enum.reduce(FDB.Machine.init(db, prefix), &FDB.Machine.execute/2)

    IO.inspect("done")
  end
end

args = System.argv()
FDB.BindingTester.run(Enum.at(args, 0), String.to_integer(Enum.at(args, 1)), Enum.at(args, 2))
