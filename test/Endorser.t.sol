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
    uint256 _feeScalingFactor,
    uint256 _baseFeeNormalizationFactor
  ) external {
    endorser.setHandler(address(_entrypoint), false);
    vm.expectRevert("invalid handler: ".c(_entrypoint).b());

    IEndorser.Operation memory op;

    op.entrypoint = _entrypoint;
    op.data = _data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = _feeToken;
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = _baseFeeNormalizationFactor;

    endorser.isOperationReady(op);
  }

  function testRejectUnsupportedToken(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    address _feeToken,
    uint256 _feeScalingFactor,
    uint256 _baseFeeNormalizationFactor
  ) external {
    vm.assume(_feeToken != address(token));
    vm.expectRevert("unsupported token: ".c(_feeToken).b());

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = _data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = _feeToken;
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = _baseFeeNormalizationFactor;

    endorser.isOperationReady(op);
  }

  function testRejectInsufficientGas(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _baseFeeNormalizationFactor
  ) external {
    _gasLimit = bound(_gasLimit, 0, 119_999);
    vm.expectRevert("insufficient gas: ".c(_gasLimit).c(" < 120000".s()).b());

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = _data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = _baseFeeNormalizationFactor;

    endorser.isOperationReady(op);
  }

  function testRejectBadNormFactor(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _baseFeeNormalizationFactor
  ) external {
    vm.assume(_baseFeeNormalizationFactor != 1e18);
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("Normalization factor mismatch: ".c(1e18).c(" != ".s()).c(_baseFeeNormalizationFactor).b());

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = _data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = _baseFeeNormalizationFactor;

    endorser.isOperationReady(op);
  }

  function testRejectUntrustedContext(
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("untrusted context not needed");

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = _data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;
    op.hasUntrustedContext = true;

    endorser.isOperationReady(op);
  }

  function testRejectBadFunctionSelector(
    bytes4 _badSelector,
    bytes calldata _data,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor
  ) external {
    vm.assume(_badSelector != handler.doTransfer.selector);
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    vm.expectRevert("invalid selector: "
      .c(abi.encodePacked(_badSelector))
      .c(" != ".s())
      .c(abi.encodePacked(handler.doTransfer.selector))
      .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = abi.encodePacked(_badSelector, _data);
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;
    op.hasUntrustedContext = false;

    endorser.isOperationReady(op);
  }

  function testRejectBadFeeToken(
    address _badFeeToken,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor
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
      "Fee token mismatch: "
        .c(_badFeeToken)
        .c(" != ".s())
        .c(address(token))
        .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;
    op.hasUntrustedContext = false;

    endorser.isOperationReady(op);
  }

  function testRejectTransferToSelf(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _feeScalingFactor = bound(_feeScalingFactor, 0, 1_000_000_000 ether);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(token),
      0,
      0,
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _feeScalingFactor,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("transfer to self token");

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectExpiredDeadline(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
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
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _feeScalingFactor,
      _gasLimit,
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

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectBadInnerGas(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _innerGas,
    uint256 _deadline
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max - 1);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _innerGas = bound(_innerGas, _gasLimit + 1, type(uint256).max);

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

    vm.expectRevert("Inner gas limit exceeds operation gas limit: "
      .c(_innerGas)
      .c(" > ".s())
      .c(_gasLimit)
      .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectBadInnerMaxFeePerGas(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _deadline,
    uint256 _innerMaxFeePerGas
  ) external {
    _gasLimit = bound(_gasLimit, 120_000, type(uint256).max);
    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _maxFeePerGas = bound(_maxFeePerGas, 1, type(uint256).max);
    _innerMaxFeePerGas = bound(_innerMaxFeePerGas, 0, _maxFeePerGas - 1);

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

    vm.expectRevert("Max fee per gas is less than operation max fee per gas: "
      .c(_innerMaxFeePerGas)
      .c(" < ".s())
      .c(_maxFeePerGas)
      .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectBadInnerPriorityFee(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _deadline,
    uint256 _innerPriorityFee
  ) external {
    _maxPriorityFeePerGas = bound(_maxPriorityFeePerGas, 1, type(uint256).max);
    _innerPriorityFee = bound(_innerPriorityFee, 0, _maxPriorityFeePerGas - 1);
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

    vm.expectRevert("Max priority fee per gas is less than operation max priority fee per gas: "
      .c(_innerPriorityFee)
      .c(" < ".s())
      .c(_maxPriorityFeePerGas)
      .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectBadInnerScaling(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
    uint256 _deadline,
    uint256 _innerScalingFactor
  ) external {
    vm.assume(_innerScalingFactor != _feeScalingFactor);

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
      _innerScalingFactor,
      _gasLimit,
      bytes32(0),
      bytes32(0),
      uint8(0)
    );

    vm.expectRevert("Scaling factor mismatch: "
      .c(_innerScalingFactor)
      .c(" != ".s())
      .c(_feeScalingFactor)
      .b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectIfBadPermission(
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    uint256 _feeScalingFactor,
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
    _feeScalingFactor = bound(_feeScalingFactor, 1, type(uint64).max);

    bytes memory data = abi.encodeWithSelector(
      handler.doTransfer.selector,
      address(token),
      address(0),
      address(0),
      0,
      _deadline,
      _maxPriorityFeePerGas,
      _maxFeePerGas,
      _feeScalingFactor,
      _gasLimit,
      bytes32(_r),
      bytes32(_s),
      uint8(_v)
    );

    vm.expectRevert();

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _maxPriorityFeePerGas;
    op.feeToken = address(token);
    op.feeScalingFactor = _feeScalingFactor;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
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

    vm.assume(_to != address(token));

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);
    _baseFeeRate = bound(_baseFeeRate, 0, 1_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit * _baseFeeRate) / 1e18;
    vm.assume(maxSpend != 0);

    bytes32 ophash = handler.getOpHash(
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit
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

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _priorityFee;
    op.feeToken = address(token);
    op.feeScalingFactor = _baseFeeRate;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
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

    vm.assume(_to != address(token));

    _deadline = bound(_deadline, block.timestamp, type(uint256).max);
    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);
    _baseFeeRate = bound(_baseFeeRate, 0, 1_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit * _baseFeeRate) / 1e18;
    vm.assume(maxSpend != 0);

    bytes32 ophash = handler.getOpHash(
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit
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

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _priorityFee;
    op.feeToken = address(token);
    op.feeScalingFactor = _baseFeeRate;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
  }

  function testRejectUnluckyOpHash(
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

    _gasLimit = bound(_gasLimit, 120_000, 30_000_000);
    _maxFeePerGas = bound(_maxFeePerGas, 0, 100000 gwei);
    _value = bound(_value, 0, 1_000_000_000_000_000_000 ether);
    _baseFeeRate = bound(_baseFeeRate, 0, 1_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit * _baseFeeRate) / 1e18;
    vm.assume(maxSpend != 0);

    uint256 ophash256 = uint256(handler.getOpHash(
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit
    ));

    // Ensure ophash < block.timestamp <= deadline
    vm.assume(ophash256 < _deadline);
    vm.warp(_deadline);

    bytes32 digest = keccak256(abi.encodePacked(
      hex"1901",
      token.DOMAIN_SEPARATOR(),
      keccak256(abi.encode(
          keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
          from,
          address(handler),
          maxSpend,
          0,
          ophash256
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

    vm.expectRevert(
      "invalid ophash: ".c(ophash256).c(" < ".s()).c(block.timestamp).b()
    );

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _priorityFee;
    op.feeToken = address(token);
    op.feeScalingFactor = _baseFeeRate;
    op.feeNormalizationFactor = 1e18;

    endorser.isOperationReady(op);
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
    _baseFeeRate = bound(_baseFeeRate, 0, 1_000_000_000 ether);

    address from = vm.addr(_pk);
    vm.assume(_to != from);

    uint256 maxSpend =  _value + (_maxFeePerGas * _gasLimit * _baseFeeRate) / 1e18;
    vm.assume(maxSpend != 0);

    bytes32 ophash = handler.getOpHash(
      address(token),
      from,
      _to,
      _value,
      _deadline,
      _priorityFee,
      _maxFeePerGas,
      _baseFeeRate,
      _gasLimit
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

    IEndorser.Operation memory op;
    op.entrypoint = address(handler);
    op.data = data;
    op.gasLimit = _gasLimit;
    op.maxFeePerGas = _maxFeePerGas;
    op.maxPriorityFeePerGas = _priorityFee;
    op.feeToken = address(token);
    op.feeScalingFactor = _baseFeeRate;
    op.feeNormalizationFactor = 1e18;

    (
      bool readiness,
      IEndorser.GlobalDependency memory globalDependency,
      IEndorser.Dependency[] memory dependencies
    ) = endorser.isOperationReady(op);

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
