defmodule FDB.Option do
  require FDB.OptionBuilder

  FDB.OptionBuilder.defoptions()
  FDB.OptionBuilder.defvalidators()
end
