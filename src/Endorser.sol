// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "solady/tokens/ERC20.sol";
import { IEndorser } from "erc5189-libs/interfaces/IEndorser.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { LibString } from "solady/utils/LibString.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import {
  LibDependencyCarrier,
  DependencyCarrier
} from "erc5189-libs/utils/LibDependencyCarrier.sol";

import { Handler } from "./Handler.sol";
import { LibString2 } from "./libs/LibString2.sol";
import { ERC20SlotMap } from "./mappers/ERC20SlotMap.sol";

struct ERC20Config {
  ERC20SlotMap slotMap;
  bytes slotMapData;
  uint256 minGas;
}

contract Endorser is IEndorser, Ownable {
  using LibDependencyCarrier for *;
  using FixedPointMathLib for *;
  using LibString for *;
  using LibString2 for *;

  event SetHandler(address indexed handler, bool valid);
  event SetConfig(
    address indexed token,
    address slotMap,
    bytes slotMapData,
    uint256 minGas
  );

  constructor (address _owner) {
    _initializeOwner(_owner);
  }

  mapping(address => bool) public validHandler;
  mapping(address => ERC20Config) public configForToken;

  function setHandler(address _handler, bool _valid) external onlyOwner {
    emit SetHandler(_handler, _valid);
    validHandler[_handler] = _valid;
  }

  function setConfig(
    address _token,
    address _slotMap,
    bytes calldata _slotMapData,
    uint256 _minGas
  ) external onlyOwner {
    emit SetConfig(_token, _slotMap, _slotMapData, _minGas);
    configForToken[_token] = ERC20Config({
      slotMap: ERC20SlotMap(_slotMap),
      slotMapData: _slotMapData,
      minGas: _minGas
    });
  }

  function isOperationReady(
    address _entrypoint,
    bytes calldata _data,
    bytes calldata _endorserCalldata,
    uint256 _gasLimit,
    uint256 _maxFeePerGas,
    uint256 _maxPriorityFeePerGas,
    address _feeToken,
    uint256 _baseFeeScalingFactor,
    uint256 _baseFeeNormalizationFactor,
    bool _hasUntrustedContext
  ) external returns (
    bool readiness,
    GlobalDependency memory globalDependency,
    Dependency[] memory dependencies
  ) {
    if (!validHandler[_entrypoint]) {
      revert("invalid handler: ".c(_entrypoint));
    }

    ERC20Config memory cfg = configForToken[_feeToken];
    if (cfg.minGas == 0) {
      if (_hasUntrustedContext) {
        // TODO: This is incorrect, it should simulate everything instead
        cfg.minGas = 150_000;
      } else {
        revert("unsupported token: ".c(_feeToken));
      }
    }

    if (cfg.minGas > _gasLimit) {
      revert("insufficient gas: ".c(_gasLimit).c(" < ".s()).c(cfg.minGas));
    }

    if (_baseFeeNormalizationFactor != 1e18) {
      revert("normalization factor != 1e18: ".c(_baseFeeNormalizationFactor));
    }

    // Decode the data
    bytes memory sig = _data[0:4];
    bytes memory pselector = abi.encodePacked(Handler.doTransfer.selector);
    if (keccak256(sig) != keccak256(pselector)) {
      revert("invalid selector: ".c(sig).c(" != ".s()).c(pselector));
    }

    (
      address token,
      address from,
      address to,
      uint256 value,
      uint256 deadline,
      uint256 priorityFee,
      uint256 maxFeePerGas,
      uint256 baseFeeRate,
      uint256 gas,
      bytes32 r,
      bytes32 s,
      uint8 v
    ) = abi.decode(
      _data[4:],
      (
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes32,
        bytes32,
        uint8
      )
    );

    if (token != _feeToken) {
      revert("invalid inner token: ".c(token).c(" != ".s()).c(_feeToken));
    }

    if (to == token) {
      revert("transfer to self token");
    }

    if (deadline < block.timestamp) {
      revert("expired deadline: ".c(deadline).c(" < ".s()).c(block.timestamp));
    }

    if (gas != _gasLimit) {
      revert("invalid inner gas: ".c(gas).c(" != ".s()).c(_gasLimit));
    }

    if (maxFeePerGas != _maxFeePerGas) {
      revert("invalid inner max fee per gas: ".c(maxFeePerGas).c(" != ".s()).c(_maxFeePerGas));
    }

    if (priorityFee != _maxPriorityFeePerGas) {
      revert("invalid inner priority fee: ".c(priorityFee).c(" != ".s()).c(_maxPriorityFeePerGas));
    }

    if (baseFeeRate != _baseFeeScalingFactor) {
      revert("invalid inner base fee: ".c(baseFeeRate).c(" != ".s()).c(_baseFeeScalingFactor));
    }

    bytes32 ophash = keccak256(
      abi.encodePacked(
        token,
        from,
        to,
        value,
        deadline,
        maxFeePerGas,
        priorityFee,
        baseFeeRate,
        gas
      )
    );

    // Compute how much we will need to pay in fees.
    // Notice that all units are in ERC20 except block.basefee
    // NOTICE this will catch any overflows
    // but the fee won't directly be used.
    uint256 feePerGas = maxFeePerGas.min(block.basefee + priorityFee);
    uint256 fee = (feePerGas * gas).mulWad(baseFeeRate);
    fee = fee;

    uint256 maxFee = (maxFeePerGas * gas).mulWad(baseFeeRate);

    // See if the signature is valid, easier way to do this
    // is just to call `permit`, if it reverts we know it's invalid
    uint256 combined = value + maxFee;
    ERC20(token).permit(
      from,
      _entrypoint,
      combined,
      uint256(ophash),
      v,
      r,
      s
    );

    DependencyCarrier memory dc;

    if (_hasUntrustedContext) {
      emit UntrustedStarted();

      // Doing some fetches will automatically add the dependencies
      ERC20(token).nonces(from);

      uint256 balance = ERC20(token).balanceOf(from);
      if (balance < combined) {
        revert("insufficient balance: ".c(balance).c(" < ".s()).c(combined));
      }

      emit UntrustedEnded();

      dc = LibDependencyCarrier.create();
    } else {
      // The user should have enough balance to pay for the fee and the value
      uint256 balance = ERC20(token).balanceOf(from);
      if (balance < combined) {
        revert("insufficient balance: ".c(balance).c(" < ".s()).c(combined));
      }

      // Now we need to build the dependency graph, as a summary we depend on:
      // - the user balance slot
      // - the user nonce slot
      // - (if the deadline is < 2 ** 64 -1) the timestamp of the deadline
      if (address(cfg.slotMap) == address(0)) {
        revert("slot map not found: ".c(token));
      }

      dc = cfg.slotMap.getSlotsDependencies(token, from, to, cfg.slotMapData);
    }

    // Add the deadline (if it's not infinite)
    if (deadline < type(uint64).max) {
      dc.addMaxBlockTimestamp(deadline);
    }

    return (true, dc.globalDependency, dc.dependencies);
  }
}
