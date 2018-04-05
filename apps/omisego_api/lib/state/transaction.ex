defmodule OmiseGO.API.State.Transaction do
  @moduledoc """
  Internal representation of a spend transaction on Plasma chain
  """

  alias OmiseGO.API.State.Transaction.{Signed}
  alias OmiseGO.API.Crypto

  @zero_address <<0::size(160)>>

  # TODO: probably useful to structure these fields somehow ore readable like
  # defstruct [:input1, :input2, :output1, :output2, :fee], with in/outputs as structs or tuples?
  defstruct blknum1: 0,
            txindex1: 0,
            oindex1: 0,
            blknum2: 0,
            txindex2: 0,
            oindex2: 0,
            newowner1: 0,
            amount1: 0,
            newowner2: 0,
            amount2: 0,
            fee: 0

  def create_from_utxos(%{utxos: [_, _, _ | _]}, _, _) do
    {:error, :to_many_utxo}
  end

  def create_from_utxos(
        %{address: change_address, utxos: utxos},
        %{address: receiver_address, amount: amount},
        fee
      ) do
    stream_parts_transaction =
      utxos |> Enum.with_index(1)
      |> Enum.map(fn {utxo, number} ->
        %{
          String.to_existing_atom("blknum#{number}") => utxo.blknum,
          String.to_existing_atom("txindex#{number}") => utxo.txindex,
          String.to_existing_atom("oindex#{number}") => utxo.oindex,
          amount: utxo.amount
        }
      end)

    all_amount = Enum.reduce(stream_parts_transaction, 0, &(&1.amount + &2))

    transaction =
      Enum.reduce(stream_parts_transaction, %{}, fn part_transaction, acc ->
        {_, part_transaction} = Map.pop(part_transaction, :amount)
        Map.merge(acc, part_transaction)
      end)

    transaction =
      struct!(
        __MODULE__,
        Map.merge(transaction, %{
          newowner1: receiver_address,
          amount1: amount,
          newowner2: change_address,
          amount2: all_amount - amount - fee,
          fee: fee
        })
      )

    case validate(transaction) do
      :ok -> {:ok, transaction}
      {:error, _} = error -> error
    end
  end

  defp validate(%__MODULE__{} = transaction) do
    cond do
      transaction.amount1 < 0 -> {:error, :amount_negative_value}
      transaction.amount2 < 0 -> {:error, :amount_negative_value}
      transaction.fee < 0 -> {:error, :fee_negative_value}
      true -> :ok
    end
  end

  # TODO: add convenience function for creating common transactions (1in-1out, 1in-2out-with-change, etc.)

  def zero_address, do: @zero_address

  def account_address?(address), do: address != @zero_address

  def encode(%__MODULE__{} = tx) do
    [
      tx.blknum1,
      tx.txindex1,
      tx.oindex1,
      tx.blknum2,
      tx.txindex2,
      tx.oindex2,
      tx.newowner1,
      tx.amount1,
      tx.newowner2,
      tx.amount2,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def hash(%__MODULE__{} = tx) do
    tx
    |> encode
    |> Crypto.hash()
  end

  def sign(%__MODULE__{} = tx, priv1, priv2) do
    encoded_tx = encode(tx)
    signature1 = Crypto.signature(encoded_tx, priv1)
    signature2 = Crypto.signature(encoded_tx, priv2)

    %Signed{raw_tx: tx, sig1: signature1, sig2: signature2}
  end
end
