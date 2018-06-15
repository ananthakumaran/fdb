defmodule FDBSegfaultTest do
  use ExUnit.Case
  use ExUnitProperties

  require TestUtils
  import TestUtils

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

  def cluster() do
    FDB.Cluster.create()
  end

  def database() do
    FDB.Cluster.create()
    |> FDB.Database.create()
  end
end
