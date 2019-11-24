defmodule FDB.NativeTest do
  use ExUnit.Case, async: false
  import FDB.Native

  @current 620

  test "get_max_api_version" do
    assert get_max_api_version() >= @current
  end

  test "select_api_version_impl" do
    assert_raise ErlangError, ~r/runtime_version/, fn ->
      select_api_version_impl("hello", @current)
    end

    assert_raise ErlangError, ~r/header_version/, fn ->
      select_api_version_impl(@current, "hello")
    end

    assert select_api_version_impl(@current, @current)
    assert select_api_version_impl(@current + 100, @current) == 2201
  end

  test "get_error" do
    assert get_error(2202) == "API version not valid"
    assert get_error(2201) == "API version may be set only once"
    assert get_error(0) == "Success"
    assert get_error(42) == "UNKNOWN_ERROR"
  end
end
