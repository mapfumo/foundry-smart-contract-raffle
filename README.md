# Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

**Documentation:**

https://book.getfoundry.sh/

## Testing

### Coverage Report

```bash
$ forge coverage --report debug > coverage.txt
```

This gives you a detailed report of the coverage of your tests (which lines of code, functions, conditions, etc. are covered by your tests).

### Getting `emitted` events data into tests

```solidity
import {Vm} from "forge-std/Vm.sol";
```

vm.recordLogs() and Vm.Log[] memory:

- `vm.recordLogs()` records all events that have been emitted during the execution of the current test.
- `Vm.Log[] memory`: An array of structs representing recorded events, each containing event data.

## General Notes

### `calldata` and `memory`

Use `memory` when you need a modifiable, temporary copy of data within a function.
Use `calldata` for external/public function parameters that should remain read-only, offering better gas efficiency.

### CEF - Check Effect interactions Pattern

The Check-Effects-Interactions Pattern (CEF) in Solidity is a best practice to ensure safe and secure contract operations. This pattern help mitigating re-entry attacks, etc. It follows three steps:

1. **Check:** Validate conditions and requirements at the start of the function.
2. **Effects:** Update the contract's state variables.
3. **Interactions:** Make external calls (e.g., send ether, call another contract).

```shell
forge install smartcontractkit/chainlink-brownie-contracts --no-commit
```

update your foundry.toml to include the following in the `remappings`

```toml
remappings = [
  '@chainlink/contracts/=lib/chainlink-brownie-contracts/contracts/src/',
]
```

## Foundry Cheat Codes

1. `vm.warp(block.timestamp + 100);` // warps the block timestamp to 100 seconds from now
2. `vm.roll(block.number + 100);` // rolls the block number to 100 blocks from now
3. `vm.recordLogs()` records all events that have been emitted during the execution of the current test.
4. `Vm.Log[] memory`: An array of structs representing recorded events, each containing event data.
5. `vm.hoax(address);` set's up a `prank` from an address hat has some ether (defaults to 2^128 wei)
