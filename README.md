# ERC5189 for ERC20 Tokens

This is a simple implementation of an ERC-5189 handler for ERC-20 tokens. It allows the creation of ERC-5189 operations for any ERC-20 token that supports the `permit` extension.

## Goal

The goal of this project is to demonstrate the flexibility of ERC-5189, as it can be integrated with any ERC-20 token even if the token wasn't designed with 5189 in mind.

It has two main components:

### Handler

The handler is a simple contract that takes an ERC20 permit and executes a `transferFrom` to perform a transfer, and another `transferFrom` to `tx.origin` to pay for the fee. It re-uses the `permit` signature to allow for a single signature to perform all actions.

It takes a `maxFeePerGas` and a `priorityFeePerGas` to calculate the fee to be paid, similar to the EIP-1559 fee structure. It also takes a `feeRate` to convert the resulting fee (in the native token) to the token to be paid.

### Endorser

The endorser is a simple ERC-5189 endorser that validates operations that use the handler. It checks for the following conditions:

- The operation has enough gas limit.
- The operation uses a good handler.
- The token is supported (by the endorser).
- The handler calldata is correctly formatted.
- The 5189 fee token is the same as the token to be transferred.
- The maxFeePerGas is correct.
- The priorityFeePerGas is correct.
- The feeRate is correct.
- The deadline is not expired.
- The signature for the `permit` is correct.
- The user has enough balance to pay for the fee and the transfer.

If all conditions are met, the endorser will return `readiness = true`, and the operation can be executed. The endorser also returns a list of dependencies that may trigger a re-evaluation of the operation:

- The storage slot with the balance of the sender.
- The storage slot with the nonce of the sender.

## Limitations

a) The endorser must be manually configured for each token; for this reason, each endorser has an owner that can set the correct parameters. The handler does not enforce the use of a specific endorser, so multiple endorsers can be used if needed.

b) The endorser has no control over possible "blacklists" or any other additional restrictions that ERC20 tokens may impose. To utilize the handler with one of these tokens, a custom endorser must be created that accounts for these edge cases.

## Deployment

This repository contains a script to deploy the contracts to a network. The script will deploy the handler and the endorser, and it will configure the endorser with the correct parameters.

The script will configure the endorser for the token supplied in the `.env` file. Rerunning this script will update the configuration.

Copy the `.env.sample` file and update the values.

```sh
cp .env.sample .env
# Manually update the values
```

Deploy and configure the contracts.

```sh
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

### Token Configuration

Only tokens that support ERC20 Permit can be used with this handler.

The configure a token, you must know which slots are used for balance and nonce. If you do not know, you can use the [Map Slot Finder](https://github.com/Agusx1211/MapSlotFinder) tool to find them.

Set the configuration values in the `.env` file with the values.

Below is an example for [`USDC` on Arbitrum](https://arbiscan.io/token/0xaf88d065e77c8cc2239327c5edb3a432268e5831).

The `balance` is stored using slot `9` and nonce using slot `17`. These values are abi encoded and stored in the `TOKEN_SLOT_MAP_DATA` variable. `cast abi-encode "x(uint256,uint256)" 9 17` will generate the correct value.

```
TOKEN_ADDR=0xaf88d065e77c8cc2239327c5edb3a432268e5831
TOKEN_USE_SOLADY=false
TOKEN_MIN_GAS=160000
TOKEN_SLOT_MAP_DATA=0x00000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000011
```
