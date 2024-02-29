// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";


library Cheats {
  function boundPk(uint256 _a) internal pure returns (uint256) {
    return FixedPointMathLib.clamp(
      _a,
      1,
      0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139
    );
  }
}
