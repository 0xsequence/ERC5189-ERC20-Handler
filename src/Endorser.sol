// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "solady/tokens/ERC20.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { LibString } from "solady/utils/LibString.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { IEndorser } from "erc5189-libs/interfaces/IEndorser.sol";
import { LibDc, Dc } from "erc5189-libs/LibDc.sol";

import { Handler } from "./Handler.sol";
import { LibString2 } from "./libs/LibString2.sol";
import { ERC20SlotMap } from "./mappers/ERC20SlotMap.sol";

struct ERC20Config {
  ERC20SlotMap slotMap;
  bytes slotMapData;
  uint256 minGas;
}

contract Endorser is IEndorser, Ownable {
  using FixedPointMathLib for *;
  using LibString for *;
  using LibString2 for *;
  using LibDc for *;

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
    IEndorser.Operation calldata _op
  ) external returns (bool, GlobalDependency memory, Dependency[] memory) {
    Dc memory dc = LibDc.create(_op);
    if (_op.hasUntrustedContext) {
      revert("untrusted context not needed");
    }

    if (!validHandler[_op.entrypoint]) {
      revert("invalid handler: ".c(_op.entrypoint));
    }

    ERC20Config memory cfg = configForToken[_op.feeToken];
    if (cfg.minGas == 0) {
      revert("unsupported token: ".c(_op.feeToken));
    }

    if (_op.gasLimit < cfg.minGas) {
      revert("insufficient gas: ".c(_op.gasLimit).c(" < ".s()).c(cfg.minGas));
    }

    dc.requireNormalizationFactor(1e18);

    // Decode the data
    bytes memory sig = _op.data[0:4];
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
      _op.data[4:],
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

    dc.requireFeeToken(token)
      .requireInnerGasLimit(gas)
      .requireMaxFeePerGas(maxFeePerGas)
      .requireMaxPriorityFeePerGas(priorityFee)
      .requireScalingFactor(baseFeeRate);

    if (to == token) {
      revert("transfer to self token");
    }

    if (deadline < block.timestamp) {
      revert("expired deadline: ".c(deadline).c(" < ".s()).c(block.timestamp));
    }

    uint256 ophash256 = uint256(
      keccak256(
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
      )
    );

    if (ophash256 < block.timestamp) {
      // Unlucky hash. In this rare scenario, increment deadline and retry.
      revert("invalid ophash: ".c(ophash256).c(" < ".s()).c(block.timestamp));
    }

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
      _op.entrypoint,
      combined,
      ophash256,
      v,
      r,
      s
    );

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

    // Add the deadline (if it's not infinite)
    if (deadline < type(uint64).max) {
      dc.addMaxBlockTimestamp(deadline);
    }

    return dc.build();
  }

  function simulationSettings(
    IEndorser.Operation calldata _op
  ) external view returns (Replacement[] memory replacements) { }
}
