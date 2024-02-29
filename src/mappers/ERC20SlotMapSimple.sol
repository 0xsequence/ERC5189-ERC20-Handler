// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
  LibDependencyCarrier,
  DependencyCarrier
} from "erc5189-libs/utils/LibDependencyCarrier.sol";

import { LibSlot } from "erc5189-libs/utils/LibSlot.sol";

import { ERC20SlotMap } from "./ERC20SlotMap.sol";

/**
  Simple ERC20 slot map implementation.
  it uses the input data to get the slots only for the balance
  of the from address and the nonce of the from address.

  It does not account for:
  - Freezing of funds
  - Forbidden addresses
  - Upgradeability
 */
contract ERC20SlotMapSimple is ERC20SlotMap {
  using LibDependencyCarrier for *;

  function getSlotsDependencies(
    address _token,
    address _from,
    address,
    bytes calldata _data
  ) external pure returns (DependencyCarrier memory dc) {
    (
      bytes32 fromBalanceSlot,
      bytes32 fromNonceSlot
    ) = abi.decode(_data, (bytes32, bytes32));
    dc = LibDependencyCarrier.create();
    dc.addSlotDependency(
      _token,
      LibSlot.getMappingStorageSlot(
        fromBalanceSlot,
        _from
      )
    );
    dc.addSlotDependency(
      _token,
      LibSlot.getMappingStorageSlot(
        fromNonceSlot,
        _from
      )
    );
  }
}
