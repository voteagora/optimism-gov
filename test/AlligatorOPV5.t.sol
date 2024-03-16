// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AlligatorOP.t.sol";
import {SubdelegationRules as SubdelegationRulesV3} from "src/structs/RulesV3.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AlligatorOPV5Mock} from "./mocks/AlligatorOPV5Mock.sol";

contract AlligatorOPV5Test is AlligatorOPTest {
    bytes32 internal constant BALLOT_TYPEHASH_V5 =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority)");
    bytes32 internal constant BALLOT_WITHPARAMS_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority,string reason,bytes params)");
    bytes32 internal constant BALLOT_WITHPARAMS_BATCHED_TYPEHASH = keccak256(
        "Ballot(uint256 proposalId,uint8 support,uint256 maxVotingPower,address[][] authorities,string reason,bytes params)"
    );

    function setUp() public virtual override {
        SetupAlligatorOP.setUp();
        alligatorAlt = address(new AlligatorOPV5Mock());
        bytes memory initData = abi.encodeCall(AlligatorOPV5Mock(alligator).initialize, address(this));
        alligator = address(new ERC1967Proxy(alligatorAlt, initData));
        alligatorAlt = alligator;

        proxy1 = _proxyAddress(address(this), baseRules, baseRulesHash);
        proxy2 = _proxyAddress(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _proxyAddress(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreate() public override {}

    function testCastVoteTwice() public virtual {
        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.alice;
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        standardCastVote(authority2);

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 50e18);

        vm.prank(Utils.alice);
        subdelegationRules = SubdelegationRules({
            baseRules: baseRules,
            allowanceType: AllowanceType.Relative,
            allowance: 7.5e4 // 75%
        });
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);
        standardCastVote(authority2);

        (, forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 75e18);
    }

    function testCastVoteMaxRedelegations() public virtual {
        uint256 length = 255;
        subdelegationRules.allowanceType = AllowanceType.Absolute;
        address[] memory authority = new address[](length + 1);
        authority[0] = Utils.alice;
        for (uint256 i = 0; i < length; i++) {
            address delegator = i == 0 ? authority[0] : address(uint160(i));
            address delegate = address(uint160(i + 1));
            subdelegationRules.allowance = 1e18 - 10 * i;
            vm.prank(delegator);
            _subdelegate(delegator, baseRules, delegate, subdelegationRules);

            authority[i + 1] = delegate;
        }

        // startMeasuringGas("castVote with max chain length - partial allowances");
        vm.startPrank(address(uint160(length)));
        standardCastVote(authority);
        vm.stopPrank();
        // stopMeasuringGas();
    }

    function testCastVoteTwiceWithTwoChains_Alt() public virtual {
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, voter, subdelegationRules);
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(Utils.bob, baseRules, Utils.carol, subdelegationRules);
        vm.prank(voter);
        _subdelegate(voter, baseRules, Utils.carol, subdelegationRules);

        address[] memory authority1 = new address[](3);
        authority1[0] = Utils.alice;
        authority1[1] = voter;
        authority1[2] = Utils.carol;

        address[] memory authority2 = new address[](3);
        authority2[0] = Utils.alice;
        authority2[1] = Utils.bob;
        authority2[2] = Utils.carol;

        address[][] memory authorities = new address[][](2);
        authorities[1] = authority1;
        authorities[0] = authority2;

        address[] memory proxies = new address[](2);
        proxies[0] = _proxyAddress(Utils.alice, baseRules, baseRulesHash);
        proxies[1] = _proxyAddress(Utils.alice, baseRules, baseRulesHash);

        BaseRules[] memory proxyRules = new BaseRules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        bytes32[] memory proxyRulesHashes = new bytes32[](2);
        proxyRulesHashes[0] = baseRulesHash;
        proxyRulesHashes[1] = baseRulesHash;

        standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, "reason", "params"
        );

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 50e18);
    }

    function testCastVoteTwiceWithTwoChains() public virtual {
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, Utils.carol, subdelegationRules);
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(Utils.bob, baseRules, Utils.carol, subdelegationRules);

        address[] memory authority1 = new address[](2);
        authority1[0] = Utils.alice;
        authority1[1] = Utils.carol;

        address[] memory authority2 = new address[](3);
        authority2[0] = Utils.alice;
        authority2[1] = Utils.bob;
        authority2[2] = Utils.carol;

        address[][] memory authorities = new address[][](2);
        authorities[1] = authority1;
        authorities[0] = authority2;

        address[] memory proxies = new address[](2);
        proxies[0] = _proxyAddress(Utils.alice, baseRules, baseRulesHash);
        proxies[1] = _proxyAddress(Utils.alice, baseRules, baseRulesHash);

        BaseRules[] memory proxyRules = new BaseRules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        bytes32[] memory proxyRulesHashes = new bytes32[](2);
        proxyRulesHashes[0] = baseRulesHash;
        proxyRulesHashes[1] = baseRulesHash;

        standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, "reason", "params"
        );

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 75e18);
    }

    function testLimitedCastVoteWithReasonAndParamsBatched() public virtual {
        (address[][] memory authorities,, BaseRules[] memory proxyRules, bytes32[] memory proxyRulesHashes) =
            _formatBatchData();

        standardLimitedCastVoteWithReasonAndParamsBatched(
            1e12, authorities, proxyRules, proxyRulesHashes, "reason", "params"
        );
    }

    function testLimitedCastVoteWithReasonAndParamsBatchedBySig() public virtual {
        (address[][] memory authorities,,,) = _formatBatchDataSigner();

        standardLimitedCastVoteWithReasonAndParamsBatchedBySig(1e12, authorities);
    }

    function testSubdelegate() public virtual override {
        _subdelegate(address(this), baseRules, Utils.alice, subdelegationRules);

        (
            uint8 maxRedelegations,
            uint16 blocksBeforeVoteCloses,
            uint32 notValidBefore,
            uint32 notValidAfter,
            address customRule,
            AllowanceType allowanceType,
            uint256 allowance
        ) = AlligatorOPV5Mock(alligator).subdelegations(address(this), Utils.alice);

        BaseRules memory baseRulesSet =
            BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

        subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
    }

    function testSubdelegateBatched() public virtual override {
        address[] memory targets = new address[](2);
        targets[0] = address(Utils.bob);
        targets[1] = address(Utils.alice);

        _subdelegateBatched(address(this), baseRules, targets, subdelegationRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (
                uint8 maxRedelegations,
                uint16 blocksBeforeVoteCloses,
                uint32 notValidBefore,
                uint32 notValidAfter,
                address customRule,
                AllowanceType allowanceType,
                uint256 allowance
            ) = AlligatorOPV5Mock(alligator).subdelegations(address(this), targets[i]);

            BaseRules memory baseRulesSet =
                BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

            subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
        }
    }

    function testSubdelegateBatchedAlt() public virtual {
        address[] memory targets = new address[](2);
        targets[0] = address(Utils.bob);
        targets[1] = address(Utils.alice);

        SubdelegationRulesV3[] memory subRules = new SubdelegationRulesV3[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            subRules[i] = SubdelegationRulesV3(
                uint8(i + 1),
                subdelegationRules.baseRules.blocksBeforeVoteCloses,
                subdelegationRules.baseRules.notValidBefore,
                subdelegationRules.baseRules.notValidAfter,
                subdelegationRules.baseRules.customRule,
                subdelegationRules.allowanceType,
                subdelegationRules.allowance
            );
        }

        _subdelegateBatched(address(this), baseRules, targets, subRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (
                uint8 maxRedelegations,
                uint16 blocksBeforeVoteCloses,
                uint32 notValidBefore,
                uint32 notValidAfter,
                address customRule,
                AllowanceType allowanceType,
                uint256 allowance
            ) = AlligatorOPV5Mock(alligator).subdelegations(address(this), targets[i]);

            BaseRules memory baseRulesSet =
                BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

            assertEq(baseRulesSet.maxRedelegations, subRules[i].maxRedelegations);
            assertEq(baseRulesSet.notValidBefore, subRules[i].notValidBefore);
            assertEq(baseRulesSet.notValidAfter, subRules[i].notValidAfter);
            assertEq(baseRulesSet.blocksBeforeVoteCloses, subRules[i].blocksBeforeVoteCloses);
            assertEq(baseRulesSet.customRule, subRules[i].customRule);
            assertEq(uint8(allowanceType), uint8(subRules[i].allowanceType));
            assertEq(allowance, subRules[i].allowance);
        }
    }

    function testValidate() public {
        SubdelegationRules memory subRules = subdelegationRules;
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        address proxy = _proxyAddress(authority[0], baseRules, baseRulesHash);
        uint256 proxyTotalVotes = op.getPastVotes(proxy, governor.proposalSnapshot(proposalId));

        (uint256 votesToCast, uint256 k) = AlligatorOPV5Mock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes);
        assertEq(k, 0);

        authority = new address[](2);
        authority[0] = address(Utils.alice);
        authority[1] = address(this);

        subRules.allowance = 2e4;
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subRules);

        (votesToCast, k) = AlligatorOPV5Mock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes * subRules.allowance / 1e5);
        assertEq(k, 1);

        subRules.allowance = 1e5;
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subRules);

        (votesToCast, k) = AlligatorOPV5Mock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes * subRules.allowance / 1e5);
        assertEq(k, 0);

        subRules.allowanceType = AllowanceType.Absolute;
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subRules);

        (votesToCast, k) = AlligatorOPV5Mock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, subRules.allowance);
        assertEq(k, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_castVoteBatched_ZeroVotesToCast() public virtual override {
        super.testRevert_castVoteBatched_ZeroVotesToCast();

        (address[][] memory authorities,, BaseRules[] memory proxyRules, bytes32[] memory proxyRulesHashes) =
            _formatBatchData();

        vm.expectRevert(ZeroVotesToCast.selector);
        vm.prank(Utils.carol);
        _limitedCastVoteWithReasonAndParamsBatched(
            200, proxyRules, proxyRulesHashes, authorities, proposalId, 1, "reason", "params"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function standardCastVote(address[] memory authority) public virtual override {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, "", "");
        super.standardCastVote(authority);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    function standardCastVoteWithReason(address[] memory authority, string memory reason) public virtual override {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, reason, "");
        super.standardCastVoteWithReason(authority, reason);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    function standardCastVoteWithReasonAndParams(address[] memory authority, string memory reason, bytes memory params)
        public
        virtual
        override
    {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, reason, params);
        super.standardCastVoteWithReasonAndParams(authority, reason, params);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    mapping(address proxy => uint256) public votesToCast_;

    function standardCastVoteWithReasonAndParamsBatched(
        address[][] memory authorities,
        address[] memory proxies,
        BaseRules[] memory proxyRules,
        bytes32[] memory proxyRulesHashes,
        string memory reason,
        bytes memory params
    ) public virtual override {
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory k = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast;

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (, votesToCast[i], k[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        super.standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, reason, params
        );

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, k, initWeightCast, initForVotes, initWeights
        );
    }

    function standardLimitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotingPower,
        address[][] memory authorities,
        BaseRules[] memory proxyRules,
        bytes32[] memory proxyRulesHashes,
        string memory reason,
        bytes memory params
    ) public virtual {
        address[] memory proxies = new address[](authorities.length);
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory k = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast;

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (proxies[i], votesToCast[i], k[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];

            if (totalVotesToCast > maxVotingPower) {
                votesToCast_[proxies[i]] -= votesToCast[i];
                votesToCast[i] = maxVotingPower - (totalVotesToCast - votesToCast[i]);
                votesToCast_[proxies[i]] += votesToCast[i];
                totalVotesToCast = maxVotingPower;
                break;
            }
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        vm.expectEmit();
        emit VotesCast(proxies, Utils.carol, authorities, proposalId, 1);

        vm.prank(Utils.carol);
        _limitedCastVoteWithReasonAndParamsBatched(
            maxVotingPower, proxyRules, proxyRulesHashes, authorities, proposalId, 1, reason, params
        );

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, k, initWeightCast, initForVotes, initWeights
        );
    }

    function standardCastVoteBySig(address[] memory authority) public virtual override {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH_V5, proposalId, 1, authority));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(vm.envUint("SIGNER_KEY"), keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), signer, authority, proposalId, 1);
        _castVoteBySig(baseRules, baseRulesHash, authority, proposalId, 1, v, r, s);
    }

    function standardCastVoteWithReasonAndParamsBySig(address[] memory authority) public virtual override {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash = keccak256(
            abi.encode(
                BALLOT_WITHPARAMS_TYPEHASH, proposalId, 1, authority, keccak256(bytes("reason")), keccak256("params")
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(vm.envUint("SIGNER_KEY"), keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), signer, authority, proposalId, 1);
        _castVoteWithReasonAndParamsBySig(
            baseRules, baseRulesHash, authority, proposalId, 1, "reason", "params", v, r, s
        );
    }

    function standardLimitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] memory authorities
    ) public virtual {
        address[] memory proxies = new address[](authorities.length);
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory k = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast;

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (proxies[i], votesToCast[i], k[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];

            if (totalVotesToCast > maxVotingPower) {
                votesToCast_[proxies[i]] -= votesToCast[i];
                votesToCast[i] = maxVotingPower - (totalVotesToCast - votesToCast[i]);
                votesToCast_[proxies[i]] += votesToCast[i];
                totalVotesToCast = maxVotingPower;
                break;
            }
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, "reason", "params"
        );
        vm.expectEmit();
        emit VotesCast(proxies, signer, authorities, proposalId, 1);

        _limitedCastVoteWithReasonAndParamsBatchedBySig(maxVotingPower, authorities, proposalId, 1, "reason", "params");

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, k, initWeightCast, initForVotes, initWeights
        );
    }

    function _getInitParams(address[] memory authority)
        internal
        returns (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights)
    {
        proxy = _proxyAddress(authority[0], baseRules, baseRulesHash);
        uint256 proxyTotalVotes = op.getPastVotes(proxy, governor.proposalSnapshot(proposalId));
        (votesToCast, k) = AlligatorOPV5Mock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );
        votesToCast_[proxy] += votesToCast;
        initWeightCast = governor.weightCast(proposalId, proxy);
        initWeights = new uint256[](authority.length);
        for (uint256 i = 1; i < authority.length; ++i) {
            initWeights[i] = AlligatorOPV5Mock(alligator).votesCast(proxy, proposalId, authority[i - 1], authority[i]);
        }
    }

    function _castVoteAssertions(
        address[] memory authority,
        address proxy,
        uint256 votesToCast,
        uint256 k,
        uint256 initWeightCast,
        uint256 initForVotes,
        uint256[] memory initWeights
    ) internal {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertTrue(governor.hasVoted(proposalId, proxy));
        assertEq(governor.weightCast(proposalId, proxy), initWeightCast + votesToCast);
        assertEq(finalForVotes, initForVotes + votesToCast);

        for (uint256 i = 1; i < authority.length; ++i) {
            uint256 recordedVotes =
                AlligatorOPV5Mock(alligator).votesCast(proxy, proposalId, authority[i - 1], authority[i]);
            assertEq(recordedVotes, (k == 0 || i < k) ? initWeights[i] : initWeights[i] + votesToCast);
        }
    }

    function _castVoteBatchedAssertions(
        address[][] memory authorities,
        address[] memory proxies,
        uint256[] memory votesToCast,
        uint256 totalVotesToCast,
        uint256[] memory k,
        uint256[] memory initWeightCast,
        uint256 initForVotes,
        uint256[][] memory initWeights
    ) internal {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertEq(finalForVotes, initForVotes + totalVotesToCast);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            address proxy = proxies[i];

            if (proxy != address(0)) {
                assertTrue(governor.hasVoted(proposalId, proxy));
                assertEq(governor.weightCast(proposalId, proxy), initWeightCast[i] + votesToCast_[proxy]);

                for (uint256 l = 1; l < authority.length; ++l) {
                    uint256 recordedVotes =
                        AlligatorOPV5Mock(alligator).votesCast(proxy, proposalId, authority[l - 1], authority[l]);
                    assertEq(
                        recordedVotes, (k[i] == 0 || l < k[i]) ? initWeights[i][l] : initWeights[i][l] + votesToCast[i]
                    );
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _proxyAddress(address proxyOwner, BaseRules memory, bytes32)
        internal
        view
        override
        returns (address computedAddress)
    {
        return AlligatorOPV5Mock(alligator).proxyAddress(proxyOwner);
    }

    function _create(address proxyOwner, BaseRules memory baseRules_, bytes32 baseRulesHash_)
        internal
        view
        override
        returns (address computedAddress)
    {
        return _proxyAddress(proxyOwner, baseRules_, baseRulesHash_);
    }

    function _subdelegate(address, BaseRules memory, address to, SubdelegationRules memory subdelegateRules)
        internal
        override
    {
        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(
            subdelegateRules.baseRules.maxRedelegations,
            subdelegateRules.baseRules.blocksBeforeVoteCloses,
            subdelegateRules.baseRules.notValidBefore,
            subdelegateRules.baseRules.notValidAfter,
            subdelegateRules.baseRules.customRule,
            subdelegateRules.allowanceType,
            subdelegateRules.allowance
        );
        AlligatorOPV5Mock(alligator).subdelegate(to, rules);
    }

    function _subdelegateBatched(
        address,
        BaseRules memory,
        address[] memory targets,
        SubdelegationRules memory subdelegateRules
    ) internal virtual override {
        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(
            subdelegateRules.baseRules.maxRedelegations,
            subdelegateRules.baseRules.blocksBeforeVoteCloses,
            subdelegateRules.baseRules.notValidBefore,
            subdelegateRules.baseRules.notValidAfter,
            subdelegateRules.baseRules.customRule,
            subdelegateRules.allowanceType,
            subdelegateRules.allowance
        );
        AlligatorOPV5Mock(alligator).subdelegateBatched(targets, rules);
    }

    function _subdelegateBatched(
        address,
        BaseRules memory,
        address[] memory targets,
        SubdelegationRulesV3[] memory subdelegateRules
    ) internal virtual {
        AlligatorOPV5Mock(alligator).subdelegateBatched(targets, subdelegateRules);
    }

    function _castVote(BaseRules memory, bytes32, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
        override
    {
        AlligatorOPV5Mock(alligator).castVote(authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual override {
        AlligatorOPV5Mock(alligator).castVoteWithReason(authority, propId, support, reason);
    }

    function _castVoteWithReasonAndParams(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        AlligatorOPV5Mock(alligator).castVoteWithReasonAndParams(authority, propId, support, reason, params);
    }

    function _castVoteWithReasonAndParamsBatched(
        BaseRules[] memory,
        bytes32[] memory,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        AlligatorOPV5Mock(alligator).castVoteWithReasonAndParamsBatched(authorities, propId, support, reason, params);
    }

    function _limitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotingPower,
        BaseRules[] memory,
        bytes32[] memory,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        AlligatorOPV5Mock(alligator).limitedCastVoteWithReasonAndParamsBatched(
            maxVotingPower, authorities, propId, support, reason, params
        );
    }

    function _castVoteBySig(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual override {
        AlligatorOPV5Mock(alligator).castVoteBySig(authority, propId, support, v, r, s);
    }

    function _castVoteWithReasonAndParamsBySig(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual override {
        AlligatorOPV5Mock(alligator).castVoteWithReasonAndParamsBySig(
            authority, propId, support, reason, params, v, r, s
        );
    }

    function _limitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            vm.envUint("SIGNER_KEY"),
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator)),
                    keccak256(
                        abi.encode(
                            BALLOT_WITHPARAMS_BATCHED_TYPEHASH,
                            proposalId,
                            1,
                            maxVotingPower,
                            authorities,
                            keccak256(bytes("reason")),
                            keccak256("params")
                        )
                    )
                )
            )
        );

        AlligatorOPV5Mock(alligator).limitedCastVoteWithReasonAndParamsBatchedBySig(
            maxVotingPower, authorities, propId, support, reason, params, v, r, s
        );
    }
}
