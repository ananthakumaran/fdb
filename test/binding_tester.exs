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
    coder = Dynamic.new()
    value = coder.module.encode(List.to_tuple(items), coder.opts)
    %{s | stack: [value | stack]}
  end

  def execute({id, {{_, op}}}, s) when op in ["NEW_TRANSACTION", "RESET"] do
    :ok = TransactionMap.put(s.transaction_name, Transaction.create(s.db))
    s
  end <
    def execute({id, {{_, "GET_READ_VERSION"}}}, s) do
      %{
        s
        | last_version: Transaction.get_read_version(trx(s)),
          stack: [{:unicode_string, "GOT_READ_VERSION"} | s.stack]
      }
    end

  def execute({id, {{_, "SET"}}}, s) do
    [key | [value | stack]] = s.stack
    :ok = Transaction.set(trx(s), key, value)
    %{s | stack: stack}
  end

  def execute({id, {{_, "CLEAR_DATABASE"}}}, s) do
    [key | stack] = s.stack

    t = Transaction.create(s.db)
    :ok = Transaction.clear(t, key)
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

  defp trx(s) do
    FDB.TransactionMap.get(s.transaction_name)
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
