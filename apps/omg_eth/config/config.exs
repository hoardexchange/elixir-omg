use Mix.Config

config :ethereumex,
  url: System.get_env("ETHEREUM_RPC_URL") || "http://localhost:8545"

config :omg_eth,
  contract_addr: nil,
  authority_addr: nil,
  txhash_contract: nil,
  # "geth" | "parity"
  eth_node: {:system, "ETH_NODE", "geth"},
  node_logging_in_debug: true,
  child_block_interval: 1000,
  exit_period_seconds: {:system, "EXIT_PERIOD_SECONDS", 7 * 24 * 60 * 60, {String, :to_integer}}

import_config "#{Mix.env()}.exs"
