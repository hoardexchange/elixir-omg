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

defmodule OMG.API.Utxo do
  @moduledoc """
  Manipulates a single unspent transaction output (UTXO) held be the child chain state.
  """

  alias OMG.API.Crypto
  alias OMG.API.State.Transaction

  defstruct [:owner, :currency, :amount, :tokenids, :creating_txhash]

  @type t() :: %__MODULE__{
          creating_txhash: Transaction.Recovered.tx_hash_t(),
          owner: Crypto.address_t(),
          currency: Crypto.address_t(),
          amount: non_neg_integer
        }
        |
        %__MODULE__{
            creating_txhash: Transaction.Recovered.tx_hash_t(),
            owner: Crypto.address_t(),
            currency: Crypto.address_t(),
            tokenids: [non_neg_integer]
        }

  @doc """
  Inserts a representation of an UTXO position, usable in guards. See Utxo.Position for handling of these entities
  """
  defmacro position(blknum, txindex, oindex) do
    quote do
      {:utxo_position, unquote(blknum), unquote(txindex), unquote(oindex)}
    end
  end
end
