## FDB client benchmark result

The script used to run the benchmark is available at [bench.exs](bench.exs). Random
string of size 16 bytes is used for key and of size from 8 to 100
bytes is used for value.

`read/write 1 op` -  a transaction with a single read/write operation.<br>
`read/write 10 op` -  a transaction with 10 read/write operation.

The benchmark is run at multiple concurrency level and only the top
result(based on operation per second) for each type is shown here. The
main intention is to show that FDB client could saturate the server by
generating enough load.

```
           name    concurrency     ops/s   average ms    max ms    min ms   deviation
    read   1 op             40     52237        0.766      3.79     0.442     ±29.08%
    read  10 op             40     90990        4.396    11.893     1.647     ±16.32%
    write  1 op           2000     33738       59.279   165.896    37.971      ±26.4%
    write 10 op            500     73195        68.31     88.74    43.387      ±8.05%
```

### Machine Spec

```
Operating System: macOS"
CPU Information: Intel(R) Core(TM) i7-4770HQ CPU @ 2.20GHz
Number of Available Cores: 8
Available memory: 16 GB
Elixir 1.6.5
Erlang 20.3.6
```

### Cluster Spec

```
Configuration:
  Redundancy mode        - single
  Storage engine         - memory
  Coordinators           - 1

Cluster:
  FoundationDB processes - 1
  Machines               - 1
  Fault Tolerance        - 0 machines
```
