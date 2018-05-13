defmodule FDB.RawTest do
  use ExUnit.Case

  test "get_max_api_version" do
    assert FDB.Raw.get_max_api_version() == 510
  end
end
