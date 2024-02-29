// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";

import { LibString } from "solady/utils/LibString.sol";
import { IEndorser } from "erc5189-libs/interfaces/IEndorser.sol";

import { LibString2 } from "../src/libs/LibString2.sol";

import { Endorser } from "../src/Endorser.sol";
import { Handler } from "../src/Handler.sol";
import { TestERC20 } from "./utils/TestERC20.sol";
import { Cheats } from "./utils/Cheats.sol";
import { ERC20SlotMap } from "../src/mappers/ERC20SlotMap.sol";
import { ERC20SlotMapSimpleSolady } from "../src/mappers/ERC20SlotMapSimpleSolady.sol";

contract EndorserTest is Test {
  using LibString for *;
  using LibString2 for *;
  using Cheats for *;

  Handler handler;
  TestERC20 token;
  Endorser endorser;
  ERC20SlotMap slotMap;

  function setUp() external {
    handler = new Handler();
    token = new TestERC20();
    slotMap = new ERC20SlotMapSimpleSolady();

    endorser = new Endorser(address(this));
    endorser.setHandler(address(handler), true);
    endorser.setConfig(address(token), address(slotMap), bytes(""), 120_000);
  }

  function testRejectBadHandler(
    address _entrypoint,
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    address _feeToken,
    uint256 _baseFeeScalingFactor,
    uint256 _baseFeeNormalizationFactor,
    bool _hasUntrustedContext
  ) external {
    endorser.setHandler(address(_entrypoint), false);
    vm.expectRevert("invalid handler: ".c(_entrypoint).b());
    endorser.isOperationReady(
      _entrypoint,
      _data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      _feeToken,
      _baseFeeScalingFactor,
      _baseFeeNormalizationFactor,
      _hasUntrustedContext
    );
  }

  function testRejectUnsupportedToken(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    address _feeToken,
    uint256 _baseFeeScalingFactor,
    uint256 _baseFeeNormalizationFactor,
    bool _hasUntrustedContext
  ) external {
    vm.assume(_feeToken != address(token));
    vm.expectRevert("unsupported token: ".c(_feeToken).b());
    endorser.isOperationReady(
      address(handler),
      _data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      _feeToken,
      _baseFeeScalingFactor,
      _baseFeeNormalizationFactor,
      _hasUntrustedContext
    );
  }

  function testRejectInsufficientGas(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _baseFeeNormalizationFactor,
    bool _hasUntrustedContext
  ) external {
    _gasLimit = bound(_gasLimit, 0, 119_999);
    vm.expectRevert("insufficient gas: ".c(_gasLimit).c(" < 120000".s()).b());
    endorser.isOperationReady(
      address(handler),
      _data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      _baseFeeNormalizationFactor,
      _hasUntrustedContext
    );
  }

  function testRejectBadNormFactor(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _baseFeeNormalizationFactor,
    bool _hasUntrustedContext
  ) external {
    vm.assume(_baseFeeNormalizationFactor != 1e18);
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("normalization factor != 1e18: ".c(_baseFeeNormalizationFactor).b());
    endorser.isOperationReady(
      address(handler),
      _data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      _baseFeeNormalizationFactor,
      _hasUntrustedContext
    );
  }

  function testRejectUntrustedContext(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("untrusted context not needed");
    endorser.isOperationReady(
      address(handler),
      _data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      true
    );
  }

  function testRejectBadFunctionSelector(
    bytes4 _badSelector,
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor
  ) external {
    vm.assume(_badSelector != handler.doTransfer.selector);
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("invalid selector: "
      .c(abi.encodePacked(_badSelector))
      .c(" != ".s())
      .c(abi.encodePacked(handler.doTransfer.selector))
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      abi.encodePacked(_badSelector, _data),
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectBadFeeToken(
    address _badFeeToken,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor
  ) external {
    vm.assume(_badFeeToken != address(token));

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(_badFeeToken),
      address(0),
      address(0),
      0,
      0,
      0,
      0,
      0,
      0,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert(
      "invalid inner token: "
        .c(_badFeeToken)
        .c(" != ".s())
        .c(address(token))
        .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectTransferToSelf(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(token),
      0,
      0,
      0,
      0,
      0,
      0,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("transfer to self token");
    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
   );
  }

  function testRejectExpiredDeadline(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, 0, block.timestamp - 1);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      0,
      0,
      0,
      0,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("expired deadline: "
      .c(_deadline)
      .c(" < ".s())
      .c(block.timestamp)
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectBadInnerGas(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _innerGas,
    uint256 _deadline
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    vm.assume(_innerGas != _gasLimit);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      0,
      0,
      0,
      _innerGas,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("invalid inner gas: "
      .c(_innerGas)
      .c(" != ".s())
      .c(_gasLimit)
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectBadInnerMaxFeePerGas(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline,
    uint256 _innerMaxFeePerGas
  ) external {
    vm.assume(_innerMaxFeePerGas != _maxFeePerGas);

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      0,
      _innerMaxFeePerGas,
      0,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("invalid inner max fee per gas: "
      .c(_innerMaxFeePerGas)
      .c(" != ".s())
      .c(_maxFeePerGas)
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectBadInnerPriorityFee(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline,
    uint256 _innerPriorityFee
  ) external {
    vm.assume(_innerPriorityFee != _maxPriorityFeePerGas);

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      _innerPriorityFee,
      _maxFeePerGas,
      0,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("invalid inner priority fee: "
      .c(_innerPriorityFee)
      .c(" != ".s())
      .c(_maxPriorityFeePerGas)
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectBadInnerBasefeeScaling(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline,
    uint256 _innerBaseFee
  ) external {
    vm.assume(_innerBaseFee != _baseFeeScalingFactor);

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _innerBaseFee,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("invalid inner base fee: "
      .c(_innerBaseFee)
      .c(" != ".s())
      .c(_baseFeeScalingFactor)
      .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectOverflowBasefee(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline,
    uint256 _realBasefee
  ) external {
    _realBasefee = bound(_realBasefee, 2, type(uint256).max);
    vm.fee(_realBasefee);

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _baseFeeScalingFactor = bound(_baseFeeScalingFactor, type(uint256).max / block.basefee + 1, type(uint256).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _baseFeeScalingFactor,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert(0xbac65e5b);
    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectIfBadPermission(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _baseFeeScalingFactor,
    uint256 _deadline,
    uint256 _realBasefee,
    bytes32 _r,
    bytes32 _s,
    uint8 _v
  ) external {
    _realBasefee = bound(_realBasefee, 0, type(uint64).max);
    vm.fee(_realBasefee);

    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _baseFeeScalingFactor = bound(_baseFeeScalingFactor, 1, type(uint64).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _baseFeeScalingFactor,
      _gasLimit,
      bytes32(_r),
      bytes32(_s),
      uint8(_v)
    );

    vm.expectRevert();
    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _maxPriorityFeePerGas,
      address(token),
      _baseFeeScalingFactor,
      1e18,
      false
    );
  }

  function testRejectLowBalance(
    uint256 _pk,
    address _to,
    uint256 _value,
    uint256 _priorityFee,
    uint256 _maxFeePerGas,
    uint256 _baseFeeRate,
    uint256 _deadline,
    uint256 _gasLimit,
    uint256 _balance
  ) external {
    _pk = _pk.boundPk();

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit);
    vm.assume(maxSpend != 0);

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
        _gasLimit
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

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit,
      r,
      s,
      v
    );

    _balance = bound(_balance, 0, maxSpend - 1);
    token.mint(from, _balance);

    vm.expectRevert(
      "insufficient balance: "
        .c(_balance)
        .c(" < ".s())
        .c(maxSpend)
        .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _priorityFee,
      address(token),
      _baseFeeRate,
      1e18,
      false
    );
  }

  function testRejectSlotNotFound(
    uint256 _pk,
    address _to,
    uint256 _value,
    uint256 _priorityFee,
    uint256 _maxFeePerGas,
    uint256 _baseFeeRate,
    uint256 _deadline,
    uint256 _gasLimit,
    uint256 _balance
  ) external {
    _pk = _pk.boundPk();

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit);
    vm.assume(maxSpend != 0);

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
        _gasLimit
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

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit,
      r,
      s,
      v
    );

    _balance = bound(_balance, maxSpend, type(uint256).max);
    token.mint(from, _balance);

    endorser.setConfig(address(token), address(0), bytes(""), 120_000);

    vm.expectRevert(
      "slot map not found: "
        .c(address(token))
        .b()
    );

    endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _priorityFee,
      address(token),
      _baseFeeRate,
      1e18,
      false
    );
  }

  function testAcceptOperation(
    uint256 _pk,
    address _to,
    uint256 _value,
    uint256 _priorityFee,
    uint256 _maxFeePerGas,
    uint256 _baseFeeRate,
    uint256 _deadline,
    uint256 _gasLimit,
    uint256 _balance
  ) external {
    _pk = _pk.boundPk();

    vm.assume(_to != address(token));

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit);
    vm.assume(maxSpend != 0);

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
        _gasLimit
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

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit,
      r,
      s,
      v
    );

    _balance = bound(_balance, maxSpend, type(uint256).max);
    token.mint(from, _balance);

    (
      bool readiness,
      IEndorser.GlobalDependency memory globalDependency,
      IEndorser.Dependency[] memory dependencies
    ) = endorser.isOperationReady(
      address(handler),
      data,
      bytes(""),
      _gasLimit,
      _maxFeePerGas,
      _priorityFee,
      address(token),
      _baseFeeRate,
      1e18,
      false
    );

    assertEq(readiness, true);

    if (_deadline > type(uint64).max) {
      assertEq(globalDependency.maxBlockTimestamp, type(uint256).max);
    } else {
      assertEq(globalDependency.maxBlockTimestamp, _deadline);
    }

    assertEq(dependencies.length, 1);
    assertEq(dependencies[0].addr, address(token));
    assertEq(dependencies[0].slots.length, 2);
  }
}
