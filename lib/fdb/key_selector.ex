defmodule FDB.KeySelector do
  def last_less_than(key, offset \\ 0), do: {key, 0, 0 + offset}
  def last_less_or_equal(key, offset \\ 0), do: {key, 1, 0 + offset}
  def first_greater_than(key, offset \\ 0), do: {key, 1, 1 + offset}
  def first_greater_or_equal(key, offset \\ 0), do: {key, 0, 1 + offset}
end
