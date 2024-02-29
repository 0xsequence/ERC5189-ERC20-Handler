// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
  LibDependencyCarrier,
  DependencyCarrier
} from "erc5189-libs/utils/LibDependencyCarrier.sol";

interface ERC20SlotMap {
  function getSlotsDependencies(
    address _token,
    address _from,
    address _to,
    bytes memory _data
  ) external pure returns (DependencyCarrier memory dc);
}
