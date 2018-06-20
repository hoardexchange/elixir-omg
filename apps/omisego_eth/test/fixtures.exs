defmodule OmiseGO.Eth.Fixtures do
  @moduledoc """
  Contains fixtures for tests that require geth and contract
  """
  use ExUnitFixtures.FixtureModule

  alias OmiseGO.Eth

  deffixture geth do
    {:ok, exit_fn} = Eth.DevGeth.start()
    on_exit(exit_fn)
    :ok
  end

  deffixture contract(geth) do
    :ok = geth

    %{contract_addr: contract_addr, txhash_contract: txhash} = env = OmiseGO.Eth.DevHelpers.prepare_env!("../../")

    Application.put_env(:omisego_eth, :contract_addr, contract_addr, persistent: true)
    Application.put_env(:omisego_eth, :txhash_contract, txhash, persistent: true)

    on_exit(fn ->
      Application.put_env(:omisego_eth, :contract, nil)
      Application.put_env(:omisego_eth, :txhash_contract, nil)
    end)

    env
  end

  deffixture root_chain_contract_config(contract) do
    Application.put_env(:omisego_eth, :contract_addr, contract.contract_addr, persistent: true)
    Application.put_env(:omisego_eth, :authority_addr, contract.authority_addr, persistent: true)
    Application.put_env(:omisego_eth, :txhash_contract, contract.txhash_contract, persistent: true)

    {:ok, started_apps} = Application.ensure_all_started(:omisego_eth)

    on_exit(fn ->
      Application.put_env(:omisego_eth, :contract_addr, "0x0")
      Application.put_env(:omisego_eth, :authority_addr, "0x0")
      Application.put_env(:omisego_eth, :txhash_contract, "0x0")

      started_apps
      |> Enum.reverse()
      |> Enum.map(fn app -> :ok = Application.stop(app) end)
    end)

    :ok
  end
end
