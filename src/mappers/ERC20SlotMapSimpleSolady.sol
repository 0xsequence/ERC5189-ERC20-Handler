// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDc, Dc } from "erc5189-libs/LibDc.sol";
import { LibSlot } from "erc5189-libs/LibSlot.sol";
import { ERC20SlotMap } from "./ERC20SlotMap.sol";

/**
  Simple ERC20 slot map implementation.
  It uses the Solady ERC20 storage layout.

  It does not account for:
  - Freezing of funds
  - Forbidden addresses
  - Upgradeability
 */
contract ERC20SlotMapSimpleSolady is ERC20SlotMap {
  using LibDc for *;

  uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;
  uint256 private constant _NONCES_SLOT_SEED = 0x38377508;

  // Source: https://github.com/Vectorized/solady/blob/d699161248fdb571a35fe12f4bd3077032f33806/src/tokens/ERC20.sol
  function _nonceSlot(address _owner) internal pure returns (bytes32 r) {
      /// @solidity memory-safe-assembly
      assembly {
        mstore(0x0c, _NONCES_SLOT_SEED)
        mstore(0x00, _owner)
        r := keccak256(0x0c, 0x20)
      }
  }

  // Source: https://github.com/Vectorized/solady/blob/d699161248fdb571a35fe12f4bd3077032f33806/src/tokens/ERC20.sol
  function _balanceSlot(address _owner) internal pure returns (bytes32 r) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x0c, _BALANCE_SLOT_SEED)
      mstore(0x00, _owner)
      r := keccak256(0x0c, 0x20)
    }
  }

  function getSlotsDependencies(
    address _token,
    address _from,
    address,
    bytes calldata
  ) external pure returns (Dc memory dc) {
    dc = LibDc.create();
    dc.addSlotDependency(
      _token,
      _balanceSlot(_from)
    );
    dc.addSlotDependency(
      _token,
      _nonceSlot(_from)
    );
  }
}
