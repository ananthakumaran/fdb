defmodule FDB.NativeTest do
  use ExUnit.Case, async: false
  import FDB.Native

  test "get_max_api_version" do
    assert get_max_api_version() == 510
  end

  test "select_api_version_impl" do
    assert_raise ErlangError, ~r/runtime_version/, fn -> select_api_version_impl("hello", 510) end
    assert_raise ErlangError, ~r/header_version/, fn -> select_api_version_impl(510, "hello") end
    assert select_api_version_impl(510, 510)
    assert select_api_version_impl(600, 510) == 2201
  end

  test "get_error" do
    assert get_error(2202) == "API version not valid"
    assert get_error(2201) == "API version may be set only once"
    assert get_error(0) == "Success"
    assert get_error(42) == "UNKNOWN_ERROR"
  end

  test "can be resolved multiple times" do
    cluster_future = create_cluster()
    cluster_a = FDB.Future.resolve(cluster_future)
    assert cluster_a
    cluster_b = FDB.Future.resolve(cluster_future)
    assert cluster_b
  end
end
