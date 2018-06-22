# FDB

[![Build Status](https://secure.travis-ci.org/ananthakumaran/fdb.svg?branch=master)](http://travis-ci.org/ananthakumaran/fdb)

Foundation DB client for Elixir

## Status

Under development.

## Implementation Details

As there is no documented stable [wire
protocol](https://forums.foundationdb.org/t/how-difficult-would-it-be-to-implement-the-wire-protocol-in-other-languages/69)
the only practical option is to use the [C
API](https://apple.github.io/foundationdb/api-c.html). NIF has some
major [downsides](http://erlang.org/doc/man/erl_nif.html#WARNING)

* pre-emptive scheduling

The Foundation DB C API uses event loop architecture. Nearly all the
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

The Foundation DB C API functions are thread safe except for the
network intialization part. NIF implementation tries to avoid
concurrency problems by not mutating the values once created.

> Program testing can be used to show the presence of bugs, but never
> to show their absence!
> **Edsger W. Dijkstra**

It's still possible that there are a bugs in C API or the NIF
implementation, which could lead to VM crash.

