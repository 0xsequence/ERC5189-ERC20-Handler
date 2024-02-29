// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Handler } from "../src/Handler.sol";
import { TestERC20 } from "./utils/TestERC20.sol";
import { Cheats } from "./utils/Cheats.sol";

contract HandlerTest is Test {
  using Cheats for *;

  Handler handler;
  TestERC20 token;

  function setUp() external {
    handler = new Handler();
    token = new TestERC20();
  }

  function testRejectExpired(
    address _token,
    address _from,
    address _to,
    uint256 _value,
    uint256 _deadline,
    uint256 _priorityFee,
    uint256 _maxFeePerGas,
    uint256 _baseFeeRate,
    uint256 _gas,
    bytes32 _r,
    bytes32 _s,
    uint8 _v
  ) public {
    _deadline = bound(_deadline, 0, block.timestamp - 1);
    vm.expectRevert();
    handler.doTransfer(
      _token,
      _from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gas,
      _r,
      _s,
      _v
    );
  }

  function testSend(
    uint256 _pk,
    address _to,
    uint256 _value,
    uint256 _deadline,
    uint256 _priorityFee,
    uint256 _maxFeePerGas,
    uint256 _baseFeeRate,
    uint256 _gas
  ) external {
    _pk = _pk.boundPk();

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gas = bound(_gas, 0, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gas);
    token.mint(from, maxSpend);

    bytes32 ophash = keccak256(
      abi.encodePacked(
        address(token),
        from,
        _to,
        _value,
        _deadline,
        _maxFeePerGas,
        _priorityFee,
        _baseFeeRate,
        _gas
      )
    );

    bytes32 digest = keccak256(abi.encodePacked(
      hex"1901",
      token.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
          keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
          from,
          address(handler),
          maxSpend,
          0,
          uint256(ophash)
        )
      )
    ));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, digest);

    uint256 prevBalanceFrom = token.balanceOf(from);
    uint256 prevBalanceTo = token.balanceOf(_to);
    uint256 prevBalanceOrigin = token.balanceOf(tx.origin);

    handler.doTransfer(
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gas,
      r,
      s,
      v
    );

    uint256 blockBaseFee = (block.basefee * _baseFeeRate) / 1e18;
    uint256 runtimeFeePerGas = blockBaseFee + _priorityFee;
    uint256 feePerGas = _maxFeePerGas < runtimeFeePerGas ? _maxFeePerGas : runtimeFeePerGas;
    uint256 effectiveFee = feePerGas * _gas;

    assertEq(token.balanceOf(from), prevBalanceFrom - _value - effectiveFee);

    if (tx.origin != _to) {
      assertEq(token.balanceOf(_to), prevBalanceTo + _value);
      assertEq(token.balanceOf(tx.origin), prevBalanceOrigin + effectiveFee);
    } else {
      assertEq(token.balanceOf(_to), prevBalanceTo + _value + effectiveFee);
    }
  }
}
