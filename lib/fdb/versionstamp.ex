defmodule FDB.Versionstamp do
  @incomplete <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

  defstruct [:raw]

  def incomplete(user_version \\ 0) do
    new(@incomplete, user_version)
  end

  def new(raw) when byte_size(raw) == 12 do
    %__MODULE__{raw: raw}
  end

  def new(transaction_version, user_version)
      when byte_size(transaction_version) == 10 and is_integer(user_version) do
    new(<<transaction_version::binary-size(10), user_version::unsigned-big-integer-size(16)>>)
  end

  def version(%__MODULE__{raw: raw}), do: raw

  def transaction_version(%__MODULE__{
        raw: <<transaction::binary-size(10), _user::unsigned-big-integer-size(16)>>
      }) do
    transaction
  end

  def user_version(%__MODULE__{
        raw: <<_transaction::binary-size(10), user::unsigned-big-integer-size(16)>>
      }) do
    user
  end

  def incomplete?(versionstamp), do: transaction_version(versionstamp) == @incomplete
end
