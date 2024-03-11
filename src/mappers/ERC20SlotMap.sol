// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDc, Dc } from "erc5189-libs/LibDc.sol";

interface ERC20SlotMap {
  function getSlotsDependencies(
    address _token,
    address _from,
    address _to,
    bytes memory _data
  ) external pure returns (Dc memory dc);
}
