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

  def put_if_not_present(name, transaction) do
    Agent.update(__MODULE__, fn map ->
      case Map.get(map, name) do
        nil ->
          Map.put(map, name, transaction)

        _ ->
          map
      end
    end)
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

  def pop_tuples(stack) do
    {{:integer, i}, stack} = pop(stack)

    Enum.reduce(Enum.drop(0..i, 1), {[], stack}, fn _, {result, stack} ->
      {element, stack} = pop(stack)
      {result ++ [element], stack}
    end)
  end

  def split(stack, count \\ 1) do
    {values, stack} = Enum.split(stack, count)
    {Enum.map(values, &elem(&1, 0)), stack}
  end
end

defmodule FDB.Machine do
  alias FDB.Transaction
  alias FDB.Database
  alias FDB.TransactionMap
  alias FDB.Coder.{Dynamic, Subspace}
  alias FDB.Coder
  alias FDB.KeySelector
  alias FDB.KeyRange
  alias FDB.KeySelectorRange
  alias FDB.Option
  alias FDB.Future
  alias FDB.Utils
  alias FDB.Directory
  import Stack

  defmodule State do
    defstruct stack: [],
              db: nil,
              prefix: nil,
              transaction_name: nil,
              last_version: nil,
              debug: nil,
              snapshot: false,
              processes: [],
              dirs: [],
              dir_index: 0,
              dir_error_index: 0,
              db_transaction: nil
  end

  def init(db, prefix, debug) do
    db =
      FDB.Database.set_coder(
        db,
        %FDB.Transaction.Coder{key: Dynamic.new(), value: Dynamic.new()}
      )

    %State{
      db: db,
      prefix: prefix,
      transaction_name: prefix,
      debug: debug,
      dirs: [Directory.new()]
    }
  end

  def execute({id, instruction}, s) do
    [{:unicode_string, op} | rest] = Tuple.to_list(instruction)

    if s.debug do
      IO.puts(
        "#{String.pad_leading(to_string(id), 5)} #{String.pad_trailing(op, 20)} #{inspect(rest)}"
      )
    end

    {op, snapshot} =
      if String.contains?(op, "_SNAPSHOT") do
        {String.replace(op, "_SNAPSHOT", ""), true}
      else
        {op, false}
      end

    s = %{s | snapshot: snapshot}

    cond do
      String.contains?(op, "_DATABASE") ->
        op = String.replace(op, "_DATABASE", "")
        t = Transaction.create(s.db)
        s = %{s | db_transaction: t}
        s = do_execute(id, List.to_tuple([op | rest]), s)
        s = %{s | db_transaction: nil}

        case s.stack do
          [{_, ^id} | _] ->
            s

          _ ->
            value =
              rescue_error(fn ->
                :ok = Transaction.commit(t)
                {:byte_string, "RESULT_NOT_PRESENT"}
              end)

            if Enum.member?(["DIRECTORY_CREATE"], op) do
              s
            else
              %{s | stack: push(s.stack, value, id)}
            end
        end

      true ->
        do_execute(id, List.to_tuple([op | rest]), s)
    end
  end

  def do_execute(_id, {"START_THREAD"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    result =
      spawn_monitor(fn ->
        FDB.Runner.run(s.db, prefix)
      end)

    %{s | processes: [result | s.processes], stack: stack}
  end

  def do_execute(id, {"PUSH", value}, s) do
    %{s | stack: push(s.stack, value, id)}
  end

  def do_execute(_id, {"POP"}, s) do
    {_, stack} = pop(s.stack)
    %{s | stack: stack}
  end

  def do_execute(_id, {"DUP"}, s) do
    %{s | stack: [hd(s.stack) | s.stack]}
  end

  def do_execute(id, {"CONCAT"}, s) do
    {{type, a}, {type, b}, stack} = pop(s.stack, 2)

    %{s | stack: push(stack, {type, a <> b}, id)}
  end

  def do_execute(_id, {"EMPTY_STACK"}, s) do
    %{s | stack: []}
  end

  def do_execute(id, {"SUB"}, s) do
    {{type_a, a}, {type_b, b}, stack} = pop(s.stack, 2)

    type =
      cond do
        type_a == type_b -> type_a
        type_a == :arbitrary_integer || type_b == :arbitrary_integer -> :arbitrary_integer
      end

    %{s | stack: push(stack, {type, a - b}, id)}
  end

  def do_execute(_id, {"SWAP"}, s) do
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

  def do_execute(id, {"TUPLE_UNPACK"}, s) do
    {{:byte_string, tuple}, stack} = pop(s.stack)
    unpacked = tuple_unpack({:byte_string, tuple})

    stack =
      Enum.reduce(Tuple.to_list(unpacked), stack, fn item, stack ->
        push(stack, tuple_pack([item]), id)
      end)

    %{s | stack: stack}
  end

  def do_execute(id, {"TUPLE_SORT"}, s) do
    {{_, i}, stack} = pop(s.stack)
    {items, stack} = split(stack, i)
    sorted = tuple_sort(items)

    stack =
      Enum.reduce(sorted, stack, fn tuple, stack ->
        push(stack, tuple, id)
      end)

    %{s | stack: stack}
  end

  def do_execute(id, {"TUPLE_RANGE"}, s) do
    {{_, i}, stack} = pop(s.stack)
    {items, stack} = split(stack, i)
    {start_key, end_key} = tuple_range(items)

    stack =
      push(stack, {:byte_string, start_key}, id)
      |> push({:byte_string, end_key}, id)

    %{s | stack: stack}
  end

  def do_execute(id, {"ENCODE_DOUBLE"}, s) do
    {{_, <<n::64-float-big>>}, stack} = pop(s.stack)
    %{s | stack: push(stack, {:float64, n}, id)}
  end

  def do_execute(id, {"DECODE_DOUBLE"}, s) do
    {{_, n}, stack} = pop(s.stack)
    %{s | stack: push(stack, {:byte_string, <<n::64-float-big>>}, id)}
  end

  def do_execute(id, {"ENCODE_FLOAT"}, s) do
    {{_, <<n::32-float-big>>}, stack} = pop(s.stack)
    %{s | stack: push(stack, {:float32, n}, id)}
  end

  def do_execute(id, {"DECODE_FLOAT"}, s) do
    {{_, n}, stack} = pop(s.stack)
    %{s | stack: push(stack, {:byte_string, <<n::32-float-big>>}, id)}
  end

  def do_execute(_id, {op}, s) when op in ["NEW_TRANSACTION", "RESET"] do
    db = Database.set_coder(s.db, Transaction.Coder.new())
    :ok = TransactionMap.put(s.transaction_name, Transaction.create(db))
    s
  end

  def do_execute(_id, {"USE_TRANSACTION"}, s) do
    {{_, name}, stack} = pop(s.stack)
    db = Database.set_coder(s.db, Transaction.Coder.new())
    :ok = TransactionMap.put_if_not_present(name, Transaction.create(db))

    %{s | transaction_name: name, stack: stack}
  end

  def do_execute(_id, {"LOG_STACK"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    db =
      Database.set_coder(
        s.db,
        Transaction.Coder.new(
          Coder.Tuple.new({Coder.Identity.new(), Coder.Integer.new(), Coder.Integer.new()}),
          Coder.Identity.new()
        )
      )

    Enum.reverse(stack)
    |> Enum.with_index()
    |> Enum.chunk_every(10)
    |> Enum.each(fn chunk ->
      Database.transact(db, fn t ->
        Enum.each(chunk, fn {{item, id}, i} ->
          item =
            cond do
              is_binary(item) -> {:byte_string, item}
              true -> item
            end

          {:byte_string, binary} = tuple_pack([item])

          Transaction.set(t, {prefix, i, id}, trim(binary))
        end)
      end)
    end)

    %{s | stack: []}
  end

  def do_execute(id, {"GET_READ_VERSION"}, s) do
    version =
      rescue_error(fn ->
        Transaction.get_read_version(trx(s))
      end)

    cond do
      is_integer(version) ->
        %{
          s
          | last_version: version,
            stack: push(s.stack, {:byte_string, "GOT_READ_VERSION"}, id)
        }

      true ->
        %{s | stack: push(s.stack, version, id)}
    end
  end

  def do_execute(id, {"GET_COMMITTED_VERSION"}, s) do
    version =
      rescue_error(fn ->
        Transaction.get_committed_version(trx(s))
      end)

    cond do
      is_integer(version) ->
        %{
          s
          | last_version: version,
            stack: push(s.stack, {:byte_string, "GOT_COMMITTED_VERSION"}, id)
        }

      true ->
        %{s | stack: push(s.stack, version, id)}
    end
  end

  def do_execute(id, {"GET_VERSIONSTAMP"}, s) do
    future = Transaction.get_versionstamp_q(trx(s))
    %{s | stack: push(s.stack, future, id)}
  end

  def do_execute(id, {"GET_KEY"}, s) do
    {{:byte_string, key}, {:integer, or_equal}, {:integer, offset}, {:byte_string, prefix}, stack} =
      pop(s.stack, 4)

    result =
      rescue_error(fn ->
        result =
          Transaction.get_key(
            trx(s),
            %KeySelector{key: key, or_equal: or_equal, offset: offset},
            %{snapshot: s.snapshot}
          )

        result =
          cond do
            String.starts_with?(result, prefix) -> result
            result < prefix -> prefix
            true -> Utils.strinc(prefix)
          end

        {:byte_string, result}
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"GET_RANGE_SELECTOR"}, s) do
    {{:byte_string, begin_key}, {:integer, begin_or_equal}, {:integer, begin_offset},
     {:byte_string, end_key}, {:integer, end_or_equal}, {:integer, end_offset}, {:integer, limit},
     {:integer, reverse}, {:integer, streaming_mode}, {:byte_string, prefix},
     stack} = pop(s.stack, 10)

    result =
      rescue_error(fn ->
        Transaction.get_range(
          trx(s),
          KeySelectorRange.range(
            %KeySelector{key: begin_key, or_equal: begin_or_equal, offset: begin_offset},
            %KeySelector{key: end_key, or_equal: end_or_equal, offset: end_offset}
          ),
          %{
            limit: limit,
            reverse: reverse,
            mode: streaming_mode,
            snapshot: s.snapshot
          }
        )
        |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
        |> Enum.map(fn {key, value} -> {{:byte_string, key}, {:byte_string, value}} end)
        |> Enum.map(&Tuple.to_list/1)
        |> Enum.concat()
        |> tuple_pack()
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"GET_RANGE"}, s) do
    {{:byte_string, begin_key}, {:byte_string, end_key}, {:integer, limit}, {:integer, reverse},
     {:integer, streaming_mode}, stack} = pop(s.stack, 5)

    result =
      rescue_error(fn ->
        Transaction.get_range(
          trx(s),
          KeySelectorRange.range(
            KeySelector.first_greater_or_equal(begin_key),
            KeySelector.first_greater_or_equal(end_key)
          ),
          %{
            limit: limit,
            reverse: reverse,
            mode: streaming_mode,
            snapshot: s.snapshot
          }
        )
        |> Enum.map(fn {key, value} -> {{:byte_string, key}, {:byte_string, value}} end)
        |> Enum.map(&Tuple.to_list/1)
        |> Enum.concat()
        |> tuple_pack()
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"GET_RANGE_STARTS_WITH"}, s) do
    {{:byte_string, prefix}, {:integer, limit}, {:integer, reverse}, {:integer, streaming_mode},
     stack} = pop(s.stack, 4)

    result =
      rescue_error(fn ->
        Transaction.get_range(
          trx(s),
          KeySelectorRange.range(
            KeySelector.first_greater_or_equal(prefix),
            KeySelector.first_greater_or_equal(Utils.strinc(prefix))
          ),
          %{
            limit: limit,
            reverse: reverse,
            mode: streaming_mode,
            snapshot: s.snapshot
          }
        )
        |> Enum.map(fn {key, value} -> {{:byte_string, key}, {:byte_string, value}} end)
        |> Enum.map(&Tuple.to_list/1)
        |> Enum.concat()
        |> tuple_pack()
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"WAIT_EMPTY"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    result =
      Database.transact(s.db, fn t ->
        result =
          Transaction.get_range(
            Transaction.set_coder(t, Transaction.Coder.new()),
            KeySelectorRange.range(
              KeySelector.first_greater_or_equal(prefix),
              KeySelector.first_greater_or_equal(Utils.strinc(prefix))
            )
          )
          |> Enum.to_list()

        unless Enum.empty?(result) do
          # raise error with code 1020
          FDB.Utils.verify_ok(1020)
        end

        {:byte_string, "WAITED_FOR_EMPTY"}
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(_id, {"SET"}, s) do
    {{:byte_string, key}, {:byte_string, value}, stack} = pop(s.stack, 2)
    :ok = Transaction.set(trx(s), key, value)
    %{s | stack: stack}
  end

  def do_execute(_id, {"SET_READ_VERSION"}, s) do
    :ok = Transaction.set_read_version(trx(s), s.last_version)
    s
  end

  def do_execute(id, {"GET"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)

    result =
      rescue_error(fn ->
        value = Transaction.get(trx(s), key, %{snapshot: s.snapshot})
        {:byte_string, value || "RESULT_NOT_PRESENT"}
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(_id, {"ATOMIC_OP"}, s) do
    {{:unicode_string, op_name}, {:byte_string, key}, {:byte_string, value}, stack} =
      pop(s.stack, 3)

    op = apply(Option, String.to_atom("mutation_type_" <> String.downcase(op_name)), [])
    :ok = Transaction.atomic_op(trx(s), key, op, value)
    %{s | stack: stack}
  end

  def do_execute(id, {"ON_ERROR"}, s) do
    {{:integer, error_code}, stack} = pop(s.stack)

    value =
      rescue_error(fn ->
        Transaction.on_error(trx(s), error_code)
        {:byte_string, "RESULT_NOT_PRESENT"}
      end)

    %{s | stack: push(stack, value, id)}
  end

  def do_execute(_id, {"DISABLE_WRITE_CONFLICT"}, s) do
    :ok =
      Transaction.set_option(
        trx(s),
        Option.transaction_option_next_write_no_write_conflict_range()
      )

    s
  end

  def do_execute(id, {op}, s) when op in ["WRITE_CONFLICT_RANGE", "READ_CONFLICT_RANGE"] do
    {{:byte_string, begin_key}, {:byte_string, end_key}, stack} = pop(s.stack, 2)

    result =
      rescue_error(fn ->
        Transaction.add_conflict_range(
          trx(s),
          KeyRange.range(begin_key, end_key),
          case op do
            "READ_CONFLICT_RANGE" -> Option.conflict_range_type_read()
            "WRITE_CONFLICT_RANGE" -> Option.conflict_range_type_write()
          end
        )

        {:byte_string, "SET_CONFLICT_RANGE"}
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {op}, s) when op in ["READ_CONFLICT_KEY", "WRITE_CONFLICT_KEY"] do
    {{:byte_string, key}, stack} = pop(s.stack)

    result =
      rescue_error(fn ->
        Transaction.add_conflict_range(
          trx(s),
          KeyRange.range(key, key <> <<0x00>>),
          case op do
            "READ_CONFLICT_KEY" -> Option.conflict_range_type_read()
            "WRITE_CONFLICT_KEY" -> Option.conflict_range_type_write()
          end
        )

        {:byte_string, "SET_CONFLICT_KEY"}
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(_id, {"CLEAR"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)
    :ok = Transaction.clear(trx(s), key)
    %{s | stack: stack}
  end

  def do_execute(_id, {"CLEAR_RANGE"}, s) do
    {{:byte_string, start_key}, {:byte_string, end_key}, stack} = pop(s.stack, 2)

    :ok =
      Transaction.clear_range(
        trx(s),
        KeyRange.range(start_key, end_key)
      )

    %{s | stack: stack}
  end

  def do_execute(_id, {"CLEAR_RANGE_STARTS_WITH"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)

    :ok =
      Transaction.clear_range(
        trx(s),
        KeyRange.range(key, Utils.strinc(key))
      )

    %{s | stack: stack}
  end

  def do_execute(id, {"COMMIT"}, s) do
    value =
      rescue_error(fn ->
        :ok = Transaction.commit(trx(s))
        {:byte_string, "RESULT_NOT_PRESENT"}
      end)

    %{s | stack: push(s.stack, value, id)}
  end

  def do_execute(_id, {"CANCEL"}, s) do
    :ok = Transaction.cancel(trx(s))
    s
  end

  def do_execute(_id, {"WAIT_FUTURE"}, s) do
    # scripted test doesn't issue seperate WAIT_FUTURE for the
    # GET_VERSIONSTAMP
    size = 2

    stack =
      Enum.map(Enum.take(s.stack, size), fn {f, id} ->
        case f do
          %Future{} ->
            result = rescue_error(fn -> Future.await(f) end)

            cond do
              result in [:ok, nil] -> {{:byte_string, "RESULT_NOT_PRESENT"}, id}
              is_binary(result) -> {{:byte_string, result}, id}
              true -> {result, id}
            end

          _ ->
            {f, id}
        end
      end) ++ Enum.drop(s.stack, size)

    %{s | stack: stack}
  end

  def do_execute(_id, {"DIRECTORY_CREATE_SUBSPACE"}, s) do
    {path, stack} = pop_tuples(s.stack)
    {{:byte_string, prefix}, stack} = pop(stack)
    {:byte_string, path} = tuple_pack(path)
    %{s | stack: stack, dirs: s.dirs ++ [Subspace.new(prefix <> path)]}
  end

  def do_execute(_id, {"DIRECTORY_CREATE_LAYER"}, s) do
    {{:integer, nodei}, {:integer, contenti}, {:integer, manual}, stack} = pop(s.stack, 3)

    node_subspace = Enum.at(s.dirs, nodei)
    content_subspace = Enum.at(s.dirs, contenti)

    dir =
      if !node_subspace || !content_subspace do
        nil
      else
        Directory.new(%{
          node_subspace: node_subspace,
          content_subspace: content_subspace,
          allow_manual_prefixes: manual == 1
        })
      end

    %{s | stack: stack, dirs: s.dirs ++ [dir]}
  end

  def do_execute(_id, {"DIRECTORY_CHANGE"}, s) do
    {{:integer, i}, stack} = pop(s.stack)

    i =
      if is_nil(Enum.at(s.dirs, i)) do
        s.dir_error_index
      else
        i
      end

    %{s | stack: stack, dir_index: i}
  end

  def do_execute(_id, {"DIRECTORY_SET_ERROR_INDEX"}, s) do
    {{:integer, i}, stack} = pop(s.stack)
    %{s | stack: stack, dir_error_index: i}
  end

  def do_execute(id, {"DIRECTORY_OPEN"}, s) do
    {path, stack} = pop_tuples(s.stack)
    path = Enum.map(path, fn {:unicode_string, part} -> part end)

    {{:byte_string, layer}, stack} = pop(stack)

    try do
      new_dir = Directory.open(dir(s), trx(s), path, %{layer: layer})
      %{s | stack: stack, dirs: s.dirs ++ [new_dir]}
    rescue
      _e in [FDB.Error, ArgumentError] ->
        error = {:byte_string, "DIRECTORY_ERROR"}
        %{s | stack: push(stack, error, id), dirs: s.dirs ++ [nil]}
    end
  end

  def do_execute(id, {"DIRECTORY_CREATE"}, s) do
    {path, stack} = pop_tuples(s.stack)
    path = Enum.map(path, fn {:unicode_string, part} -> part end)
    {{:byte_string, layer}, {_, prefix}, stack} = pop(stack, 2)

    try do
      new_dir = Directory.create(dir(s), trx(s), path, %{layer: layer, prefix: prefix})
      %{s | stack: stack, dirs: s.dirs ++ [new_dir]}
    rescue
      _e in [FDB.Error, ArgumentError] ->
        error = {:byte_string, "DIRECTORY_ERROR"}
        %{s | stack: push(stack, error, id), dirs: s.dirs ++ [nil]}
    end
  end

  def do_execute(id, {"DIRECTORY_LIST"}, s) do
    {{:integer, count}, stack} = pop(s.stack)

    {path, stack} =
      case count do
        0 ->
          {[], stack}

        1 ->
          {path, stack} = pop_tuples(stack)
          path = Enum.map(path, fn {:unicode_string, part} -> part end)
          {path, stack}
      end

    result =
      rescue_dir_error(fn ->
        Directory.list(dir(s), trx(s), path)
        |> Enum.map(fn name ->
          {:unicode_string, name}
        end)
        |> tuple_pack
      end)

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(id, {"DIRECTORY_EXISTS"}, s) do
    {{:integer, count}, stack} = pop(s.stack)

    {path, stack} =
      case count do
        0 ->
          {[], stack}

        1 ->
          {path, stack} = pop_tuples(stack)
          path = Enum.map(path, fn {:unicode_string, part} -> part end)
          {path, stack}
      end

    result =
      if Directory.exists?(dir(s), trx(s), path) do
        {:integer, 1}
      else
        {:integer, 0}
      end

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(_id, {"DIRECTORY_LOG_DIRECTORY"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    tr =
      trx(
        s,
        Transaction.Coder.new(
          Subspace.new(prefix, Coder.Tuple.new({Coder.Integer.new(), Coder.UnicodeString.new()})),
          Dynamic.new()
        )
      )

    d = dir(s)

    Transaction.set(
      tr,
      {s.dir_index, "path"},
      Enum.map(d.current_node.path, fn p -> {:unicode_string, p} end)
      |> List.to_tuple()
    )

    Transaction.set(
      tr,
      {s.dir_index, "layer"},
      {:byte_string, d.current_node.layer}
    )

    children =
      Directory.list(d, trx(s))
      |> Enum.map(fn name -> {:unicode_string, name} end)
      |> List.to_tuple()

    Transaction.set(
      tr,
      {s.dir_index, "children"},
      children
    )

    Transaction.set(
      tr,
      {s.dir_index, "exists"},
      {:integer, 1}
    )

    %{s | stack: stack}
  end

  def do_execute(_id, {"DIRECTORY_LOG_SUBSPACE"}, s) do
    {{:byte_string, prefix}, stack} = pop(s.stack)

    tr =
      trx(
        s,
        Transaction.Coder.new(
          Subspace.new(prefix, Coder.Integer.new()),
          Coder.Identity.new()
        )
      )

    prefix =
      case(dir(s)) do
        %FDB.Coder{opts: opts} ->
          opts.prefix

        %FDB.Directory{current_node: current_node} ->
          current_node.prefix
      end

    Transaction.set(
      tr,
      s.dir_index,
      prefix
    )

    %{s | stack: stack}
  end

  def do_execute(id, {"DIRECTORY_PACK_KEY"}, s) do
    {tuple, stack} = pop(s.stack)
    %{s | stack: push(stack, tuple_pack([tuple]), id)}
  end

  def do_execute(id, {"TUPLE_UNPACK"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)
    unpacked = tuple_unpack({:byte_string, key})

    stack =
      Enum.reduce(Tuple.to_list(unpacked), stack, fn item, stack ->
        push(stack, tuple_pack([item]), id)
      end)

    %{s | stack: stack}
  end

  def do_execute(id, {"DIRECTORY_STRIP_PREFIX"}, s) do
    {{:byte_string, key}, stack} = pop(s.stack)
    prefix = dir(s).opts.prefix

    if !Utils.starts_with?(key, prefix) do
      raise ArgumentError, "String #{key} does not start with prefix #{prefix}"
    end

    result =
      {:byte_string, binary_part(key, byte_size(prefix), byte_size(key) - byte_size(prefix))}

    %{s | stack: push(stack, result, id)}
  end

  def do_execute(_id, {"UNIT_TESTS"}, s) do
    s
  end

  def do_execute(_id, instruction, _s) do
    raise "Unknown instruction #{inspect(instruction)}"
  end

  defp tuple_pack(items) do
    coder = Dynamic.new()
    value = coder.module.encode(List.to_tuple(items), coder.opts)
    {:byte_string, value}
  end

  defp tuple_unpack({:byte_string, binary}) do
    coder = Dynamic.new()
    {value, ""} = coder.module.decode(binary, coder.opts)
    value
  end

  defp tuple_sort(items) do
    coder = Dynamic.new()

    Enum.map(items, fn {:byte_string, item} ->
      {value, ""} = coder.module.decode(item, coder.opts)
      value
    end)
    |> Enum.map(fn item -> coder.module.encode(item, coder.opts) end)
    |> Enum.sort()
    |> Enum.map(&{:byte_string, &1})
  end

  defp tuple_range(items) do
    coder = Transaction.Coder.new(Dynamic.new())
    key = List.to_tuple(items)

    {Transaction.Coder.encode_range(coder, key, :first),
     Transaction.Coder.encode_range(coder, key, :last)}
  end

  defp dir(s) do
    Enum.at(s.dirs, s.dir_index)
  end

  defp trx(s, coder \\ Transaction.Coder.new()) do
    t =
      if s.db_transaction do
        s.db_transaction
      else
        FDB.TransactionMap.get(s.transaction_name)
      end

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

  defp rescue_dir_error(cb) do
    cb.()
  rescue
    _e in [FDB.Error, ArgumentError] ->
      {:byte_string, "DIRECTORY_ERROR"}
  end

  defp trim(binary) when byte_size(binary) > 40000 do
    binary_part(binary, 0, 40000)
  end

  defp trim(x), do: x
end

defmodule FDB.Runner do
  alias FDB.Transaction
  alias FDB.Coder.{Subspace, Dynamic}
  alias FDB.KeySelectorRange

  def run(db, prefix) do
    coder =
      Transaction.Coder.new(
        Subspace.new(prefix, FDB.Coder.Integer.new(), FDB.Coder.ByteString.new()),
        Dynamic.new()
      )

    db = FDB.Database.set_coder(db, coder)

    state =
      Transaction.get_range(
        db,
        KeySelectorRange.starts_with(nil)
      )
      |> Enum.reduce(
        FDB.Machine.init(db, prefix, System.get_env("DEBUG")),
        &FDB.Machine.execute/2
      )

    for {pid, reference} <- state.processes do
      receive do
        {:DOWN, ^reference, :process, ^pid, reason} ->
          :normal = reason
          :ok
      end
    end
  end
end

defmodule FDB.BindingTester do
  def run(prefix, version, cluster) do
    :ok = FDB.start(version)
    {:ok, _pid} = FDB.TransactionMap.start_link()

    db =
      FDB.Cluster.create(cluster)
      |> FDB.Database.create()

    FDB.Runner.run(db, prefix)
  end
end

args = System.argv()
FDB.BindingTester.run(Enum.at(args, 0), String.to_integer(Enum.at(args, 1)), Enum.at(args, 2))
