// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {Endorser, ERC20Config} from "../src/Endorser.sol";
import {Handler} from "../src/Handler.sol";
import {ERC20SlotMapSimple} from "../src/mappers/ERC20SlotMapSimple.sol";
import {ERC20SlotMapSimpleSolady} from "../src/mappers/ERC20SlotMapSimpleSolady.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(pk);
        bytes32 salt = bytes32(0);

        // Deploy

        address handler = _deployIfNotAlready("Handler", abi.encodePacked(type(Handler).creationCode), salt, pk);

        Endorser endorser = Endorser(
            _deployIfNotAlready(
                "Endorser", abi.encodePacked((type(Endorser).creationCode), abi.encode(owner)), salt, pk
            )
        );

        // Configure handler

        if (!endorser.validHandler(handler)) {
            console.log("Configuring handler");
            vm.broadcast(pk);
            endorser.setHandler(handler, true);
        } else {
            console.log("Handler already configured");
        }

        // Configure token

        address token = vm.envAddress("TOKEN_ADDR");
        if (token != address(0)) {
            (,, uint256 minGas) = endorser.configForToken(token);
            if (minGas == 0) {
                // Read from config
                minGas = vm.envUint("TOKEN_MIN_GAS");
                if (minGas == 0) {
                    revert("Missing TOKEN_MIN_GAS");
                }
                bool useSolady = vm.envBool("TOKEN_USE_SOLADY");
                address slotMap;
                // Deploy slot map
                if (!useSolady) {
                    slotMap = _deployIfNotAlready(
                        "ERC20SlotMapSimple", abi.encodePacked(type(ERC20SlotMapSimple).creationCode), salt, pk
                    );
                } else {
                    slotMap = _deployIfNotAlready(
                        "ERC20SlotMapSimpleSolady",
                        abi.encodePacked(type(ERC20SlotMapSimpleSolady).creationCode),
                        salt,
                        pk
                    );
                }
                bytes memory slotMapData = vm.envBytes("TOKEN_SLOT_MAP_DATA");
                // Update config
                console.log("Configuring token", token);
                vm.broadcast(pk);
                endorser.setConfig(token, slotMap, slotMapData, minGas);
            } else {
                console.log("Token already configured", token);
            }
        } else {
            console.log("No token to configure");
        }
    }
}
