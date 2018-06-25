defmodule FDBSegfaultTest do
  use ExUnit.Case
  use ExUnitProperties

  require TestUtils
  import TestUtils
  alias FDB.{KeySelector, KeyRange}

  fuzz(
    FDB.Network,
    :start,
    1,
    fixed_list([
      one_of([term(), integer()])
    ])
  )

  fuzz(
    FDB.Network,
    :set_option,
    1,
    fixed_list([
      one_of([term(), integer()])
    ])
  )

  fuzz(
    FDB.Network,
    :set_option,
    2,
    fixed_list([
      one_of([term(), integer()]),
      one_of([term(), integer(), binary()])
    ])
  )

  fuzz(FDB.Cluster, :create, 1, fixed_list([term()]))
  fuzz(FDB.Cluster, :create_q, 1, fixed_list([term()]))

  fuzz(
    FDB.Cluster,
    :set_option,
    2,
    fixed_list([one_of([term(), constant(cluster())]), one_of([term(), integer()])])
  )

  fuzz(
    FDB.Cluster,
    :set_option,
    3,
    fixed_list([
      one_of([term(), constant(cluster())]),
      one_of([term(), integer()]),
      one_of([term(), integer(), binary()])
    ])
  )

  fuzz(
    FDB.Database,
    :create,
    1,
    fixed_list([
      one_of([term(), constant(cluster())])
    ])
  )

  fuzz(
    FDB.Database,
    :create,
    2,
    fixed_list([
      one_of([term(), constant(cluster())]),
      term()
    ])
  )

  fuzz(
    FDB.Database,
    :create_q,
    1,
    fixed_list([
      one_of([term(), constant(cluster())])
    ])
  )

  fuzz(
    FDB.Database,
    :create_q,
    2,
    fixed_list([
      one_of([term(), constant(cluster())]),
      term()
    ])
  )

  fuzz(
    FDB.Database,
    :set_coder,
    2,
    fixed_list([
      one_of([term(), constant(database())]),
      term()
    ])
  )

  fuzz(
    FDB.Database,
    :set_option,
    2,
    fixed_list([one_of([term(), constant(database())]), one_of([term(), integer()])])
  )

  fuzz(
    FDB.Database,
    :set_option,
    3,
    fixed_list([
      one_of([term(), constant(database())]),
      one_of([term(), integer()]),
      one_of([term(), integer(), binary()])
    ])
  )

  fuzz(
    FDB.Database,
    :get_range,
    2,
    fixed_list([
      one_of([term(), constant(database())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ])
    ]),
    %{stream: true}
  )

  fuzz(
    FDB.Database,
    :get_range,
    3,
    fixed_list([
      one_of([term(), constant(database())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ]),
      one_of([
        term(),
        optional_map(%{
          limit: one_of([term(), boolean()]),
          mode: one_of([term(), integer()]),
          reverse: one_of([term(), boolean()]),
          snapshot: one_of([term(), boolean()]),
          target_bytes: one_of([term(), integer()])
        })
      ])
    ]),
    %{stream: true}
  )

  fuzz(
    FDB.Database,
    :transact,
    2,
    fixed_list([
      one_of([term(), constant(database())]),
      one_of([term(), constant(fn _ -> nil end)])
    ])
  )

  fuzz(
    FDB.Transaction,
    :create,
    1,
    fixed_list([
      one_of([term(), constant(database())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :create,
    2,
    fixed_list([
      one_of([term(), constant(database())]),
      term()
    ])
  )

  fuzz(
    FDB.Transaction,
    :set_coder,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      term()
    ])
  )

  fuzz(
    FDB.Transaction,
    :set_option,
    2,
    fixed_list([one_of([term(), constant(transaction())]), one_of([term(), integer()])])
  )

  fuzz(
    FDB.Transaction,
    :set_option,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), integer()]),
      one_of([term(), integer(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()]),
      one_of([nil, term(), optional_map(%{snapshot: one_of([term(), boolean()])})])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_q,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :get_q,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()]),
      one_of([nil, term(), optional_map(%{snapshot: one_of([term(), boolean()])})])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :get_range,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ])
    ]),
    %{stream: true}
  )

  fuzz(
    FDB.Transaction,
    :get_range,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ]),
      one_of([
        term(),
        optional_map(%{
          limit: one_of([term(), boolean()]),
          mode: one_of([term(), integer()]),
          reverse: one_of([term(), boolean()]),
          snapshot: one_of([term(), boolean()]),
          target_bytes: one_of([term(), integer()])
        })
      ])
    ]),
    %{stream: true}
  )

  fuzz(
    FDB.Transaction,
    :get_key,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_key,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ]),
      one_of([nil, term(), optional_map(%{snapshot: one_of([term(), boolean()])})])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_key_q,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :get_key_q,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ]),
      one_of([nil, term(), optional_map(%{snapshot: one_of([term(), boolean()])})])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :get_read_version,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_read_version_q,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :get_committed_version,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_versionstamp_q,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :watch_q,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_addresses_for_key,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :get_addresses_for_key_q,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :set,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()]),
      one_of([term(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :set_read_version,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), integer()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :atomic_op,
    4,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()]),
      one_of([term(), binary()]),
      one_of([term(), integer()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :clear,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), binary()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :clear_range,
    2,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ])
    ])
  )

  fuzz(
    FDB.Transaction,
    :commit,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :commit_q,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :cancel,
    1,
    fixed_list([
      one_of([term(), constant(transaction())])
    ])
  )

  fuzz(
    FDB.Transaction,
    :on_error,
    1,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), integer()])
    ])
  )

  fuzz(
    FDB.Transaction,
    :on_error_q,
    1,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([term(), integer()])
    ]),
    %{future: true}
  )

  fuzz(
    FDB.Transaction,
    :add_conflict_range,
    3,
    fixed_list([
      one_of([term(), constant(transaction())]),
      one_of([
        term(),
        constant(
          KeyRange.range(KeySelector.first_greater_than("a"), KeySelector.first_greater_than("d"))
        )
      ]),
      one_of([term(), integer()])
    ])
  )

  def cluster() do
    FDB.Cluster.create()
  end

  def database() do
    FDB.Cluster.create()
    |> FDB.Database.create()
  end

  def transaction() do
    FDB.Cluster.create()
    |> FDB.Database.create()
    |> FDB.Transaction.create()
  end
end
