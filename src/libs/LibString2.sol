// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibString } from "solady/utils/LibString.sol";


library LibString2 {
  using LibString for *;

  function s(string memory _a) internal pure returns (string memory) {
    return _a;
  }

  function b(string memory _a) internal pure returns (bytes memory) {
    return bytes(_a);
  }

  function c(string memory _a, string memory _b) internal pure returns (string memory) {
    return _a.concat(_b);
  }

  function c(string memory _a, uint256 _v) internal pure returns (string memory) {
    return _a.concat(_v.toString());
  }

  function c(string memory _a, bytes32 _b) internal pure returns (string memory) {
    return _a.concat(uint256(_b).toHexString());
  }

  function c(string memory _a, address _b) internal pure returns (string memory) {
    return _a.concat(_b.toHexStringChecksummed());
  }

  function c(string memory _a, bytes memory _b) internal pure returns (string memory) {
    return _a.concat(_b.toHexString());
  }
}
