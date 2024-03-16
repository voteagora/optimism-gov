// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV5} from "src/OptimismGovernorV5.sol";
import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";
import {OptimismGovernorV6_Manageable} from "./contracts/OptimismGovernorV6_Manageable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";
import {ApprovalVotingModule} from "src/modules/ApprovalVotingModule.sol";
import {OptimisticModule_SocialSignalling} from "src/modules/OptimisticModule.sol";

contract UpgradeOptimismGovernorToV6Script is Script {
    // Test environment addresses
    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(0x6E17cdef2F7c1598AD9DfA9A8acCF84B1303f43f));
    ProposalTypesConfigurator proposalTypesConfigurator =
        ProposalTypesConfigurator(payable(0x54c943f19c2E983926E2d8c060eF3a956a653aA7));
    ApprovalVotingModule approvalModule = ApprovalVotingModule(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df);
    OptimisticModule_SocialSignalling optimisticSocialModule =
        OptimisticModule_SocialSignalling(0x27964c5f4F389B8399036e1076d84c6984576C33);
    VotableSupplyOracle votableSupplyOracle = VotableSupplyOracle(0x1b7CA7437748375302bAA8954A2447fC3FBE44CC);
    AlligatorOPV5 alligatorV5Impl = AlligatorOPV5(0x1C3C0e1f91541656FF709014CE3B296E61CE7FF6);
    AlligatorOPV5 alligatorV5 = AlligatorOPV5(0xfD6be5F4253Aa9fBB46B2BFacf9aa6F89822f4a6);

    // Prod environment addresses
    // TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));
    // ProposalTypesConfigurator proposalTypesConfigurator =
    //     ProposalTypesConfigurator(payable(0x54c943f19c2E983926E2d8c060eF3a956a653aA7));
    // ApprovalVotingModule approvalModule = ApprovalVotingModule(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df);
    // OptimisticModule_SocialSignalling optimisticSocialModule =
    //     OptimisticModule_SocialSignalling(0x27964c5f4F389B8399036e1076d84c6984576C33);
    // VotableSupplyOracle votableSupplyOracle = VotableSupplyOracle(0x1b7CA7437748375302bAA8954A2447fC3FBE44CC);
    // AlligatorOPV5 alligatorV5Impl = AlligatorOPV5(0xA2Cf0f99bA37cCCB9A9FAE45D95D2064190075a3);
    // AlligatorOPV5 alligatorV5 = AlligatorOPV5(0x7f08F3095530B67CdF8466B7a923607944136Df0);

    function run() public 
    // returns (
    //      OptimismGovernorV6_Manageable implementation,
    //      VotableSupplyOracle votableSupplyOracle,
    //      ProposalTypesConfigurator proposalTypesConfigurator
    //      AlligatorOPV5 alligator,
    //      ApprovalVotingModule approvalModule
    //      OptimisticModule_SocialSignalling optimisticSocialModule
    // )
    {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        // address deployer = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        vm.startBroadcast(deployer);
        // Pt. 1 Deploy contracts
        // votableSupplyOracle = new VotableSupplyOracle(deployer, 0);
        // proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(proxy)));
        // alligator = new AlligatorOPV5();

        // Pt. 2 (opt.) Approve approvalModule approval -- MANAGER
        // approvalModule = new ApprovalVotingModule();
        // address prevManager = OptimismGovernorV5(payable(proxy)).manager();
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(deployer);
        // OptimismGovernorV5(payable(proxy)).setModuleApproval(approvalModule, true);
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(prevManager);

        // Pt. 2 (opt.) Approve module optimistic -- MANAGER
        // optimisticSocialModule = new OptimisticModule_SocialSignalling();
        // address prevManager = OptimismGovernorV5(payable(proxy)).manager();
        // if (prevManager != deployer) {
        //     OptimismGovernorV6_Manageable(payable(proxy))._setManager(deployer);
        // }
        // OptimismGovernorV5(payable(proxy)).setModuleApproval(address(optimisticSocialModule), true);
        // if (prevManager != deployer) {
        //     OptimismGovernorV6_Manageable(payable(proxy))._setManager(prevManager);
        // }

        // Pt. 3 Set proposal types -- MANAGER
        // address prevManager = OptimismGovernorV5(payable(proxy)).manager();
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(deployer);
        // proposalTypesConfigurator.setProposalType(0, 3000, 5000, "Default");
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(prevManager);

        // Pt. 4 Set addresses in code
        // Set addresses in `OptimismGovernorV6`
        // (only on test env) Set correct governor address in `Alligator`

        // Pt. 5 Upgrade governor
        // implementation = new OptimismGovernorV6_Manageable();
        // proxy.upgradeTo(address(implementation));

        vm.stopBroadcast();
    }
}
