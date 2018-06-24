# FDB

[![Build Status](https://secure.travis-ci.org/ananthakumaran/fdb.svg?branch=master)](http://travis-ci.org/ananthakumaran/fdb)

FoundationDB client for Elixir

## Status

Under development.

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

* an async api that will return `FDB.Future` immediatly. The caller can
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
