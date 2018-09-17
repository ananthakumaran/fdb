defmodule FDB.Versionstamp do
  @moduledoc """
  A versionstamp is a 12 byte, unique, monotonically (but not sequentially) increasing value for each committed transaction.

  `{8 byte} {2 byte} {2 byte}`

  1. The first 8 bytes are the committed version of the database.
  1. The next 2 bytes are monotonic in the serialization order for transactions.
  1. The last 2 bytes are user supplied version in big-endian format
  """
  @incomplete <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

  defstruct [:raw]
  @type t :: %__MODULE__{raw: binary}

  @doc """
  Creates an incomplete versionstamp.

  A placeholder value is used instead of the transaction
  version. When a key created with an incompleted version is passed to
  `FDB.Transaction.set_versionstamped_key/4`, the placeholder value
  will get replaced by transaction version on commit.
  """
  @spec incomplete(integer) :: t
  def incomplete(user_version \\ 0) do
    new(@incomplete, user_version)
  end

  @spec new(binary) :: t
  def new(raw) when byte_size(raw) == 12 do
    %__MODULE__{raw: raw}
  end

  @spec new(binary, integer) :: t
  def new(transaction_version, user_version)
      when byte_size(transaction_version) == 10 and is_integer(user_version) do
    new(<<transaction_version::binary-size(10), user_version::unsigned-big-integer-size(16)>>)
  end

  @doc """
  Returns the full versionstamp as binary
  """
  @spec version(t) :: binary
  def version(%__MODULE__{raw: raw}), do: raw

  @doc """
  Returns the transaction version
  """
  @spec transaction_version(t) :: binary
  def transaction_version(%__MODULE__{
        raw: <<transaction::binary-size(10), _user::unsigned-big-integer-size(16)>>
      }) do
    transaction
  end

  @doc """
  Returns the user version
  """
  @spec user_version(t) :: integer
  def user_version(%__MODULE__{
        raw: <<_transaction::binary-size(10), user::unsigned-big-integer-size(16)>>
      }) do
    user
  end

  @doc """
  Returns true if the transaction version is equal to placeholder value
  """
  @spec incomplete?(t) :: boolean
  def incomplete?(versionstamp), do: transaction_version(versionstamp) == @incomplete
end
