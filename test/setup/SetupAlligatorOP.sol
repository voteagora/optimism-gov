// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {AllowanceType, BaseRules, SubdelegationRules} from "src/structs/RulesV2.sol";
import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";
import {OptimismGovernorV2} from "src/OptimismGovernorV2.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {OptimismGovernorV6Mock} from "../mocks/OptimismGovernorV6Mock.sol";
import "../utils/Addresses.sol";
import {GovernanceToken as OptimismToken} from "src/lib/OptimismToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

abstract contract SetupAlligatorOP is Test {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error BadSignature();
    error ZeroVotesToCast();
    error NotDelegated(address from, address to);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event ProxyDeployed(address indexed owner, BaseRules proxyRules, address proxy);
    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event ProxySubdelegation(
        address indexed proxy, address indexed from, address indexed to, SubdelegationRules subdelegationRules
    );
    event ProxySubdelegations(
        address indexed proxy, address indexed from, address[] to, SubdelegationRules subdelegationRules
    );
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );
    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                            STORAGE
    // =============================================================

    OptimismToken internal op = OptimismToken(0x4200000000000000000000000000000000000042);
    OptimismGovernorV6Mock internal governor =
        OptimismGovernorV6Mock(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));

    VotableSupplyOracle internal votableSupplyOracle;
    ProposalTypesConfigurator internal proposalTypesConfigurator;

    address internal alligator = 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9;
    address internal alligatorAlt;
    address internal proxy1;
    address internal proxy2;
    address internal proxy3;
    BaseRules internal baseRules = BaseRules(
        255, // Max redelegations
        0,
        0,
        0,
        address(0)
    );
    bytes32 baseRulesHash = keccak256(abi.encode(baseRules));
    SubdelegationRules internal subdelegationRules = SubdelegationRules({
        baseRules: baseRules,
        allowanceType: AllowanceType.Relative,
        allowance: 5e4 // 50%
            // allowance: 1e5 // 100%
    });

    address deployer = makeAddr("deployer");
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    string description = "a nice description";
    address voter = makeAddr("voter");
    address altVoter = makeAddr("altVoter");
    address altVoter2 = makeAddr("altVoter2");
    uint256 proposalId;
    address signer = vm.rememberKey(vm.envUint("SIGNER_KEY"));

    struct ReducedSubdelegationRules {
        AllowanceType allowanceType;
        uint256 allowance;
    }

    // =============================================================
    //                             SETUP
    // =============================================================

    function setUp() public virtual {
        vm.etch(address(op), address(new OptimismToken()).code);
        vm.etch(address(governor), address(new OptimismGovernorV6Mock()).code);

        vm.startPrank(address(deployer));
        votableSupplyOracle = new VotableSupplyOracle(address(this), 0);
        proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(governor)));
        vm.stopPrank();

        governor.initialize(IVotesUpgradeable(address(op)), manager);
    }

    function _postSetup() internal virtual {
        vm.startPrank(op.owner());
        op.mint(address(this), 1e18);
        op.mint(voter, 1e18);
        op.mint(altVoter, 1e20);
        op.mint(altVoter2, 1e18);
        vm.stopPrank();

        vm.prank(address(this));
        op.delegate(address(this));
        vm.prank(voter);
        op.delegate(proxy1);
        vm.prank(altVoter);
        op.delegate(proxy2);
        vm.prank(altVoter2);
        op.delegate(proxy3);

        votableSupplyOracle._updateVotableSupply(op.totalSupply());
        vm.prank(manager);
        proposalTypesConfigurator.setProposalType(0, 1_000, 5_000, "Test");

        proposalId = _propose("Test");
    }

    function _propose(string memory propDescription) internal returns (uint256 propId) {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        vm.prank(manager);
        propId = governor.propose(targets, values, calldatas, propDescription);
        vm.roll(block.number + 10);
    }

    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        emit log_named_uint(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }
}

interface DelegateToken is IERC721 {
    function delegate(address delegatee) external;
}
