// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";

contract DeployAlligatorProxyScript is Script {
    function run() public returns (ERC1967Proxy proxy) {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        address alligatorImpl = address(new AlligatorOPV5());
        proxy = new ERC1967Proxy(alligatorImpl, abi.encodeCall(AlligatorOPV5.initialize, (deployer)));

        vm.stopBroadcast();
    }
}
