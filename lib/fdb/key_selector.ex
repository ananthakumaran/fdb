defmodule FDB.KeySelector do
  def last_less_than(key) when is_binary(key), do: {key, 0, 0}
  def last_less_than({key, _, _}) when is_binary(key), do: {key, 0, 0}
  def last_less_or_equal(key) when is_binary(key), do: {key, 1, 0}
  def last_less_or_equal({key, _, _}) when is_binary(key), do: {key, 1, 0}
  def first_greater_than(key) when is_binary(key), do: {key, 1, 1}
  def first_greater_than({key, _, _}) when is_binary(key), do: {key, 1, 1}
  def first_greater_or_equal(key) when is_binary(key), do: {key, 0, 1}
  def first_greater_or_equal({key, _, _}) when is_binary(key), do: {key, 0, 1}
end
