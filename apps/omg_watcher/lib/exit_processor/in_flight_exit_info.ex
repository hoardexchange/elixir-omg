# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Watcher.ExitProcessor.InFlightExitInfo do
  @moduledoc """
  Represents the bulk of information about a tracked in-flight exit.

  Internal stuff of `OMG.Watcher.ExitProcessor`
  """

  alias OMG.API.State.Transaction
  alias OMG.API.Utxo

  require Utxo
  require Transaction

  @max_inputs Transaction.max_inputs()

  # TODO: divide into inputs and outputs: prevent contract's implementation from leaking into watcher
  # https://github.com/omisego/elixir-omg/pull/361#discussion_r247926222
  @exit_map_index_range Range.new(0, @max_inputs * 2 - 1)

  @inputs_index_range Range.new(0, @max_inputs - 1)
  @outputs_index_range Range.new(@max_inputs, @max_inputs * 2 - 1)

  @max_number_of_inputs Enum.count(@inputs_index_range)

  defstruct [
    :tx,
    :contract_tx_pos,
    :tx_seen_in_blocks_at,
    :timestamp,
    :contract_id,
    :oldest_competitor,
    :eth_height,
    # piggybacking
    exit_map:
      @exit_map_index_range
      |> Enum.map(&{&1, %{is_piggybacked: false, is_finalized: false}})
      |> Map.new(),
    is_canonical: true,
    is_active: true
  ]

  @type blknum() :: pos_integer()
  @type tx_index() :: non_neg_integer()

  @type ife_contract_id() :: <<_::192>>

  @type t :: %__MODULE__{
          tx: Transaction.Signed.t(),
          # if not nil, position was proven in contract
          contract_tx_pos: Utxo.Position.t() | nil,
          # nil value means that it was not included
          # OR we haven't processed it yet
          # OR we have found and filled this data, but haven't persisted it later
          tx_seen_in_blocks_at: {Utxo.Position.t(), inclusion_proof :: binary()} | nil,
          timestamp: non_neg_integer(),
          contract_id: ife_contract_id(),
          oldest_competitor: Utxo.Position.t() | nil,
          eth_height: pos_integer(),
          exit_map: %{
            non_neg_integer() => %{
              is_piggybacked: boolean(),
              is_finalized: boolean()
            }
          },
          is_canonical: boolean(),
          is_active: boolean()
        }

  def new(tx_bytes, tx_signatures, contract_id, timestamp, is_active, eth_height) do
    with {:ok, raw_tx} <- Transaction.decode(tx_bytes) do
      chopped_sigs = for <<chunk::size(65)-unit(8) <- tx_signatures>>, do: <<chunk::size(65)-unit(8)>>

      {
        Transaction.hash(raw_tx),
        %__MODULE__{
          tx: %Transaction.Signed{
            raw_tx: raw_tx,
            sigs: chopped_sigs
          },
          timestamp: timestamp,
          contract_id: contract_id,
          is_active: is_active,
          eth_height: eth_height
        }
      }
    end
  end

  def make_db_update({_ife_hash, %__MODULE__{} = _ife} = update) do
    {:put, :in_flight_exit_info, update}
  end

  @spec piggyback(t(), non_neg_integer()) :: {:ok, t()} | {:error, :non_existent_exit | :cannot_piggyback}
  def piggyback(ife, index)

  def piggyback(%__MODULE__{exit_map: exit_map} = ife, index) when index in @exit_map_index_range do
    with exit <- Map.get(exit_map, index),
         {:ok, updated_exit} <- piggyback_exit(exit) do
      {:ok, %{ife | exit_map: Map.put(exit_map, index, updated_exit)}}
    end
  end

  def piggyback(%__MODULE__{}, _), do: {:error, :non_existent_exit}

  defp piggyback_exit(%{is_piggybacked: false, is_finalized: false}),
    do: {:ok, %{is_piggybacked: true, is_finalized: false}}

  defp piggyback_exit(_), do: {:error, :cannot_piggyback}

  @spec challenge(t(), non_neg_integer()) :: {:ok, t()} | {:error, :competitor_too_young}
  def challenge(ife, competitor_position)

  def challenge(%__MODULE__{oldest_competitor: nil} = ife, competitor_position),
    do: %{ife | is_canonical: false, oldest_competitor: Utxo.Position.decode(competitor_position)}

  def challenge(%__MODULE__{oldest_competitor: current_oldest} = ife, competitor_position) do
    with decoded_competitor_pos <- Utxo.Position.decode(competitor_position),
         true <- is_older?(decoded_competitor_pos, current_oldest) do
      %{ife | is_canonical: false, oldest_competitor: decoded_competitor_pos}
    else
      _ -> {:error, :competitor_too_young}
    end
  end

  @spec challenge_piggyback(t(), integer()) :: {:ok, t()} | {:error, :non_existent_exit | :cannot_challenge}
  def challenge_piggyback(ife, index)

  def challenge_piggyback(%__MODULE__{exit_map: exit_map} = ife, index) when index in @exit_map_index_range do
    with %{is_piggybacked: true, is_finalized: false} <- Map.get(exit_map, index) do
      {:ok, %{ife | exit_map: Map.merge(exit_map, %{index => %{is_piggybacked: false, is_finalized: false}})}}
    else
      _ -> {:error, :cannot_challenge}
    end
  end

  def challenge_piggyback(%__MODULE__{}, _), do: {:error, :non_existent_exit}

  @spec respond_to_challenge(t(), Utxo.Position.t()) ::
          {:ok, t()} | {:error, :responded_with_too_young_tx | :cannot_respond}
  def respond_to_challenge(ife, tx_position)

  def respond_to_challenge(%__MODULE__{oldest_competitor: nil, contract_tx_pos: nil} = ife, tx_position) do
    decoded = Utxo.Position.decode(tx_position)
    {:ok, %{ife | oldest_competitor: decoded, is_canonical: true, contract_tx_pos: decoded}}
  end

  def respond_to_challenge(%__MODULE__{oldest_competitor: current_oldest, contract_tx_pos: nil} = ife, tx_position) do
    decoded = Utxo.Position.decode(tx_position)

    if is_older?(decoded, current_oldest) do
      {:ok, %{ife | oldest_competitor: decoded, is_canonical: true, contract_tx_pos: decoded}}
    else
      {:error, :responded_with_too_young_tx}
    end
  end

  def respond_to_challenge(%__MODULE__{}, _), do: {:error, :cannot_respond}

  @spec finalize(t(), non_neg_integer()) :: {:ok, t()} | :unknown_output_index
  def finalize(%__MODULE__{exit_map: exit_map} = ife, output_index) do
    case Map.get(exit_map, output_index) do
      nil ->
        :unknown_output_index

      output_exit ->
        output_exit = %{output_exit | is_finalized: true}
        exit_map = Map.put(exit_map, output_index, output_exit)
        ife = %{ife | exit_map: exit_map}

        is_active =
          exit_map
          |> Map.keys()
          |> Enum.any?(fn output_index -> is_active?(ife, output_index) end)

        ife = %{ife | is_active: is_active}
        {:ok, ife}
    end
  end

  @spec get_exiting_utxo_positions(t()) :: list({:utxo_position, non_neg_integer(), non_neg_integer(), non_neg_integer})
  def get_exiting_utxo_positions(%__MODULE__{tx: %Transaction.Signed{raw_tx: tx}}) do
    Transaction.get_inputs(tx)
  end

  @spec get_piggybacked_outputs_positions(t()) :: [Utxo.Position.t()]
  def get_piggybacked_outputs_positions(%__MODULE__{tx_seen_in_blocks_at: nil}), do: []

  def get_piggybacked_outputs_positions(%__MODULE__{tx_seen_in_blocks_at: {txpos, _}, exit_map: exit_map}) do
    {_, blknum, txindex, _} = txpos

    @outputs_index_range
    |> Enum.filter(&exit_map[&1].is_piggybacked)
    |> Enum.map(&Utxo.position(blknum, txindex, &1 - @max_number_of_inputs))
  end

  def is_piggybacked?(%__MODULE__{exit_map: map}, index) when is_integer(index) do
    with {:ok, exit} <- Map.fetch(map, index) do
      Map.get(exit, :is_piggybacked)
    else
      :error -> false
    end
  end

  def is_input_piggybacked?(%__MODULE__{} = ife, index) when is_integer(index) and index < @max_inputs do
    is_piggybacked?(ife, index)
  end

  def is_output_piggybacked?(%__MODULE__{} = ife, index) when is_integer(index) and index < @max_inputs do
    is_piggybacked?(ife, index + @max_inputs)
  end

  def piggybacked_inputs(ife) do
    @inputs_index_range
    |> Enum.filter(&is_piggybacked?(ife, &1))
  end

  def piggybacked_outputs(ife) do
    @outputs_index_range
    |> Enum.filter(&is_piggybacked?(ife, &1))
    |> Enum.map(&(&1 - @max_inputs))
  end

  def is_finalized?(%__MODULE__{exit_map: map}, index) do
    with {:ok, exit} <- Map.fetch(map, index) do
      Map.get(exit, :is_finalized)
    else
      :error -> false
    end
  end

  def is_active?(%__MODULE__{} = ife, index) do
    is_piggybacked?(ife, index) and !is_finalized?(ife, index)
  end

  def is_canonical?(%__MODULE__{is_canonical: value}), do: value

  def input_to_output_piggyback_index(%{oindex: oindex}), do: oindex + @max_number_of_inputs

  @spec get_input_index(__MODULE__.t(), Utxo.Position.t()) :: non_neg_integer() | nil
  def get_input_index(%__MODULE__{tx: %Transaction.Signed{raw_tx: tx}}, utxopos) do
    {_, input_index} =
      tx
      |> Transaction.get_inputs()
      |> Enum.with_index()
      |> Enum.find(fn {pos, _index} -> pos == utxopos end)

    input_index
  end

  defp is_older?(Utxo.position(tx1_blknum, tx1_index, _), Utxo.position(tx2_blknum, tx2_index, _)),
    do: tx1_blknum < tx2_blknum or (tx1_blknum == tx2_blknum and tx1_index < tx2_index)
end
