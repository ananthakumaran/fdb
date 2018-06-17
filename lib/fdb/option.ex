defmodule FDB.Option do
  require FDB.OptionBuilder

  FDB.OptionBuilder.defoptions()
  FDB.OptionBuilder.defvalidators()

  def normalize_value(value) when is_binary(value) do
    value
  end

  def normalize_value(value) when is_integer(value) do
    <<value::64-signed-little-integer>>
  end
end
