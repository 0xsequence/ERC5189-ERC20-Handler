// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "solady/tokens/ERC20.sol";


contract TestERC20 is ERC20 {
  constructor() {}

  function name() public override pure returns (string memory) {
    return "";
  }

  function symbol() public override pure returns (string memory) {
    return "";
  }

  function mint(address _to, uint256 _value) external {
    _mint(_to, _value);
  }

  function burn(address _from, uint256 _value) external {
    _burn(_from, _value);
  }
}
