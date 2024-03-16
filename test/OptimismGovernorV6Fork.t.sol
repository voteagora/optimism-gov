// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {OptimismGovernorV5} from "../src/OptimismGovernorV5.sol";
import {AlligatorOPV5} from "../src/alligator/AlligatorOP_V5.sol";
import {OptimismGovernorV6} from "../src/OptimismGovernorV6.sol";
import {ProposalTypesConfigurator} from "../src/ProposalTypesConfigurator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OptimismGovernorV6Mock} from "./mocks/OptimismGovernorV6Mock.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {ProposalSettings as OptimisticProposalSettings} from "../src/modules/OptimisticModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "../src/modules/ApprovalVotingModule.sol";
import {AllowanceType, SubdelegationRules as SubdelegationRulesV3} from "src/structs/RulesV3.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

contract OptimismGovernorV6UpgradeTest is Test {
    address internal constant admin = 0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0;
    address internal constant manager = 0xE4553b743E74dA3424Ac51f8C1E586fd43aE226F;
    address internal constant op = 0x4200000000000000000000000000000000000042;
    ProposalTypesConfigurator internal configurator =
        ProposalTypesConfigurator(0x67ecA7B65Baf0342CE7fBf0AA15921524414C09f);
    VotingModule optimisticModule = VotingModule(0x27964c5f4F389B8399036e1076d84c6984576C33);
    VotingModule approvalModule = VotingModule(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df);
    address newAlligatorImpl = 0xA2Cf0f99bA37cCCB9A9FAE45D95D2064190075a3;
    AlligatorOPV5 alligatorProxy = AlligatorOPV5(payable(0x7f08F3095530B67CdF8466B7a923607944136Df0));
    TransparentUpgradeableProxy internal constant proxy =
        TransparentUpgradeableProxy(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));
    OptimismGovernorV6 internal implementation = OptimismGovernorV6(payable(0x0c01693a1A4C46cf9A5F56c99304EBB35C4E817a));
    OptimismGovernorV6 internal governor = OptimismGovernorV6(payable(proxy));

    function setUp() public {
        // Block number 114965363 is 17-01-2023
        vm.createSelectFork(vm.envString("OPTIMISM_RPC_URL"), 114965363);

        // vm.prank(admin);
        // proxy.upgradeToAndCall(
        //     address(implementation),
        //     abi.encodeWithSignature("_correctStateForPreviousApprovalProposals()" /* hex"10451e87" */ )
        // );
        // proxy.upgradeTo(address(implementation));
        // governor._correctStateForPreviousApprovalProposals();

        // vm.startPrank(manager);
        // OptimismGovernorV5(governor).setModuleApproval(address(approvalModule), true);
        // OptimismGovernorV5(governor).setModuleApproval(address(optimisticModule), true);
        // configurator.setProposalType(0, 3000, 5000, "Default");
        // configurator.setProposalType(1, 3000, 7500, "Super majority");
        // configurator.setProposalType(2, 0, 0, "Optimistic");

        // vm.stopPrank();

        // Upgrade alligator
        // address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(255, 0, 0, 0, address(0), AllowanceType.Absolute, 1e20);
        vm.startPrank(admin);
        ERC20Votes(op).delegate(alligatorProxy.proxyAddress(admin));
        alligatorProxy.subdelegate(manager, rules);
        vm.stopPrank();

        // vm.startBroadcast(deployer);
        // alligatorProxy.upgradeTo(newAlligatorImpl);
        // vm.stopBroadcast();
    }

    function testReinitializer() public {
        vm.expectRevert();
        governor._correctStateForPreviousApprovalProposals();
    }

    // Commented out to speed up tests
    uint256[] successfulPropIds = [
        20327152654308054166942093105443920402082671769027198649343468266910325783863,
        // 85591583404433237270543189567126336043697987369929953414380041066767718361144,
        // 46755965320953291432113738397437466520155684451527981335363452666080752126186,
        // 47864371633107534187617995773541299064963460661119440983190542488743950169122,
        // 29831001453379581627736734765818959389842109811221412662144194715522205098015,
        // 27878184270712708211495755831534918916136653803154031118511283847257927730426,
        // // Approval voting props
        102821998933460159156263544808281872605936639206851804749751748763651967264110
        // 13644637236772462780287582686131348226526824657027343360896627559283471469688,
        // 87355419461675705865096288750937924893466943101654806912041265394266455745819,
        // 96868135958111078064987938855232246504506994378309573614627090826820561655088,
        // 16633367863894036056841722161407059007904922838583677995599242776177398115322,
        // 76298930109016961673734608568752969826843280855214969572559472848313136347131,
        // 89065519272487155253137299698235721564519179632704918690534400514930936156393,
        // 103713749716503028671815481721039004389156473487450783632177114353117435138377
    ];

    uint256[] defeatedPropIds = [
        // 25353629475948605098820168047140307200589226219380649297323431722674892706917,
        // 33427192599934651870985988641044334656392659371327786207584390219532311772967,
        2803748188551238423262549847018364268422519232004056376953100549201854740200
    ];

    uint256[] canceledPropIds = [
        // 47209512763162691916934752283791420767969951049918368296503715012448877295335,
        // 112865521924956016420269923569662990074082470744114872160834915355429517264087,
        46636534028852985057549019587907124307085930851627229211262945321458256471925
    ];

    function testPreviousProps() public {
        for (uint256 i = 0; i < successfulPropIds.length; i++) {
            assertEq(
                uint256(IGovernorUpgradeable(governor).state(successfulPropIds[i])),
                uint256(IGovernorUpgradeable.ProposalState.Succeeded)
            );
        }

        for (uint256 i = 0; i < defeatedPropIds.length; i++) {
            assertEq(
                uint256(IGovernorUpgradeable(governor).state(defeatedPropIds[i])),
                uint256(IGovernorUpgradeable.ProposalState.Defeated)
            );
        }

        for (uint256 i = 0; i < canceledPropIds.length; i++) {
            assertEq(
                uint256(IGovernorUpgradeable(governor).state(canceledPropIds[i])),
                uint256(IGovernorUpgradeable.ProposalState.Canceled)
            );
        }
    }

    function testAlligator() public {
        vm.startPrank(admin);
        ERC20Votes(op).delegate(alligatorProxy.proxyAddress(admin));
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256 snapshot = block.number + governor.votingDelay();

        address[] memory authority = new address[](2);
        authority[0] = admin;
        authority[1] = manager;

        vm.startPrank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.roll(snapshot + 1);
        alligatorProxy.castVote(authority, proposalId, 1);
        vm.stopPrank();
    }

    function testPropose() public {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256 snapshot = block.number + governor.votingDelay();

        vm.startPrank(manager);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        governor.propose(targets, values, calldatas, "Test 2", 2);

        vm.roll(snapshot + 1);
        governor.castVote(proposalId, 1);

        vm.stopPrank();
    }

    function testProposeWithModule_Optimistic() public {
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));

        vm.startPrank(manager);

        governor.proposeWithModule(optimisticModule, proposalData, "Optimistic", 2);

        vm.expectRevert();
        governor.proposeWithModule(optimisticModule, proposalData, "Optimistic 2", 1);

        vm.stopPrank();
    }

    function testProposeWithModule_Approval() public {
        bytes memory proposalData = _formatApprovalProposalData();

        vm.startPrank(manager);

        governor.proposeWithModule(approvalModule, proposalData, "Approval");

        vm.stopPrank();
    }

    function _formatApprovalProposalData() public virtual returns (bytes memory proposalData) {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Call executeCallback and send 0.01 ether to receiver1
        targets1[0] = receiver1;
        values1[0] = 0.01 ether;

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Send 0.01 ether to receiver2
        targets2[0] = receiver2;
        values2[0] = 0.01 ether;
        // Transfer 100 OP tokens to receiver2
        targets2[1] = address(op);
        calldatas2[1] = abi.encodeCall(IERC20.transfer, (receiver2, 100));

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(100, targets2, values2, calldatas2, "option 2");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        return abi.encode(options, settings);
    }
}
