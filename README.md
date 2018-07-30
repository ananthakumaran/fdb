# FDB

[![Build Status](https://secure.travis-ci.org/ananthakumaran/fdb.svg?branch=master)](http://travis-ci.org/ananthakumaran/fdb)
[![Hex.pm](https://img.shields.io/hexpm/v/fdb.svg)](https://hex.pm/packages/fdb)

FoundationDB client for Elixir

## Status

API is in alpha state and backward incompatible changes may be
introduced in subsequent versions.

## Implementation Details

As there is no documented stable [wire
protocol](https://forums.foundationdb.org/t/how-difficult-would-it-be-to-implement-the-wire-protocol-in-other-languages/69)
the only practical option is to use the [C
API](https://apple.github.io/foundationdb/api-c.html). NIF has some
major [downsides](http://erlang.org/doc/man/erl_nif.html#WARNING)

* pre-emptive scheduling

The FoundationDB C API uses event loop architecture. Nearly all the
API functions are non blocking — blocking API functions are not used
by FDB. The event loop runs on a seperate thread and the communication
is done via callback functions. The callback function when invoked
will send a message to Process. This architecture makes sure the NIF
functions return immediatly and gives the control back to VM

* memory protection

This mostly comes down to careful coding. Currenly I am running the
tests under valgrind locally. With some effort it could be integrated
in travis. FDB also runs the [bindings
tester](https://forums.foundationdb.org/t/creating-new-bindings/207)
(used to test other language bindings) in travis CI.

* concurrency

The FoundationDB C API functions are thread safe except for the
network intialization part. NIF implementation tries to avoid
concurrency problems by not mutating the values once created.

> Program testing can be used to show the presence of bugs, but never
> to show their absence!
>
> **Edsger W. Dijkstra**

It's still possible that there are bugs in C API or the NIF
implementation, which could lead to VM crash.

## API Design

It's recommended to read the [Developer
Guide](https://apple.github.io/foundationdb/developer-guide.html) and
[Data
Modeling](https://apple.github.io/foundationdb/data-modeling.html) to
get a good understanding of FoundationDB. Most of the ideas apply
across all the language bindings.

### Async

Most of the operations in FDB are async in nature. FDB provides two
kinds of api

* a sync api that will block the calling process till the operation is
  done. In case of failure an exception will be raised.

* an async api that will return `t:FDB.Future.t/0` immediatly. The caller can
  later use `FDB.Future.await/1` to resolve the value, which will
  block till the operation is done or will raise an exception in case
  of failure.

The async api ends with `_q`, for example `FDB.Transaction.get/2` is
the sync version and `FDB.Transaction.get_q/2` is the async version of the same function.

### Error Handling

FoundationDB uses optimistic concurrency. When a transaction is
committed, it could get cancelled if there are other conflicting
transactions. The common idiom is to retry the cancelled transaction
till it succeeds. `FDB.Database.transact/2` function automatically
rescues and retries if the error is retriable. For this reason, the
api is designed to raise exception instead of returning `{:error,
error}`

## Installation

FDB depends on FoundationDB [client
binary](https://apple.github.io/foundationdb/api-general.html#installing-foundationdb-client-binaries)
to be installed. The version of the client binary should be `>=` FDB
library version — patch and build part in the version can be
ignored. For example, if you want to use

```elixir
{:fdb, "5.1.7-0"}
```

then you must have client binary `>= 5.1`. If you use `~>` in the
version requirement, make sure the version includes the patch
number. Only patch versions are guaranteed to be protocol compatible.

## Getting Started

Before doing anything with the library, the API version has to be set
and the network thread has to be started. `FDB.start/1` is a helper function
which does all of these.

```elixir
:ok = FDB.start(510)
```

This must be called only once. Calling it second time will result in
exception. Once started, a `t:FDB.Cluster.t/0` and
`t:FDB.Database.t/0` instance have to be created.

```elixir
db = FDB.Cluster.create(cluster_file_path)
    |> FDB.Database.create()
```

It's recommended to use a single db instance everywhere unless
multiple db with different set of options are required. There are no
performance implications with using a single db instance as none of
the method calls are serialized either via locks or GenServer et
al.

Any kind of interaction with Database requires the usage of
`t:FDB.Transaction.t/0`. There are two ways of using transaction

```elixir
FDB.Database.transact(db, fn transaction ->
  value = FDB.Transaction.get(transaction, key)
  :ok = FDB.Transaction.set(transaction, key, value <> "hello")
end)
```

```elixir
transaction = FDB.Transaction.create(db)
value = FDB.Transaction.get(transaction, key)
:ok = FDB.Transaction.set(transaction, key, value <> "hello")
:ok = Transaction.commit(transaction)
```

The first version is the preferred one. The transaction is
automatically committed after the callback returns. In case any
exception is raised inside the callback or in the commit function
call, the transaction will be retried if the error is retriable. Various
options like `max_retry_delay`, `timeout`, `retry_limit` etc can be
configured using `FDB.Transaction.set_option/3`

### Coder

Most of the language bindings implement the [tuple
layer](https://github.com/apple/foundationdb/blob/master/design/tuple.md). It
specifies how native types like integer, unicode string, bytes etc
should be encoded. The main advantage of the encoding over others is
that it preserves the natural ordering of the values, so the range
function would work as expected.

```elixir
alias FDB.{Transaction, Database, Cluster, KeySelectorRange}
alias FDB.Coder.{Integer, Tuple, NestedTuple, ByteString, Subspace}

coder =
  Transaction.Coder.new(
    Subspace.new(
      "ts",
      Tuple.new({
        # date
        NestedTuple.new({
          # year, month, date
          NestedTuple.new({Integer.new(), Integer.new(), Integer.new()}),
          # hour, minute, second
          NestedTuple.new({Integer.new(), Integer.new(), Integer.new()})
        }),
        # website
        ByteString.new(),
        # page
        ByteString.new(),
        # browser
        ByteString.new()
      }),
      ByteString.new()
    ),
    Integer.new()
  )
db =
  Cluster.create()
  |> Database.create(%{coder: coder})

Database.transact(db, fn t ->
  m = Transaction.get(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "mozilla"})
  c = Transaction.get(t, {{{2018, 03, 01}, {1, 0, 0}}, "www.github.com", "/fdb", "chrome"})
end)

range = KeySelectorRange.starts_with({{{2018, 03, 01}}})
result =
  Database.get_range(db, range)
  |> Enum.to_list()

```

A `t:FDB.Transaction.Coder.t/0` specifies how the key and value should
be encoded. The coder could be set at database or transaction
level. The transaction automatically inherits the coder from database
if not set explicitly. Under the hood all the functions use the coder
transparently to encode and decode the values. Refer
`FDB.Database.set_defaults/2` if you want to use multiple coders.

See the [documenation](https://hexdocs.pm/fdb) for more
information.

## Benchmark

A simple, unreliable and non-scientific benchmark can be found [here](BENCHMARK.md)
