## ERC5189 for ERC20 Tokens

This is a simple implementation of an ERC-5189 handler for ERC-20 tokens. It allows the creation of ERC-5189 operations for any ERC-20 token that supports the `permit` extension.

### Goal

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

### Limitations

a) The endorser must be manually configured for each token; for this reason, each endorser has an owner that can set the correct parameters. The handler does not enforce the use of a specific endorser, so multiple endorsers can be used if needed.

b) The endorser has no control over possible "blacklists" or any other additional restrictions that ERC20 tokens may impose. To utilize the handler with one of these tokens, a custom endorser must be created that accounts for these edge cases.
