// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AlligatorOP.t.sol";
import {SubdelegationRules as SubdelegationRulesV3} from "src/structs/RulesV3.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlligatorOPV4} from "src/alligator/AlligatorOP_V4.sol";
import {IAlligatorOPV4} from "src/interfaces/IAlligatorOPV4.sol";

contract AlligatorOPV4Test is AlligatorOPTest {
    function setUp() public virtual override {
        SetupAlligatorOP.setUp();

        alligatorAlt = address(new AlligatorOPV4(address(governor), address(op), address(this)));
        vm.etch(alligator, alligatorAlt.code);

        proxy1 = _proxyAddress(address(this), baseRules, baseRulesHash);
        proxy2 = _proxyAddress(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _proxyAddress(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    /*//////////////////////////////////////////////////////////////
                               OVERRIDES
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
        ) = AlligatorOPV4(alligator).subdelegations(address(this), Utils.alice);

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
            ) = AlligatorOPV4(alligator).subdelegations(address(this), targets[i]);

            BaseRules memory baseRulesSet =
                BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

            subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
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
        return IAlligatorOPV4(alligator).proxyAddress(proxyOwner);
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
        IAlligatorOPV4(alligator).subdelegate(to, rules);
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
        IAlligatorOPV4(alligator).subdelegateBatched(targets, rules);
    }

    function _castVote(BaseRules memory, bytes32, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
        override
    {
        IAlligatorOPV4(alligator).castVote(authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual override {
        IAlligatorOPV4(alligator).castVoteWithReason(authority, propId, support, reason);
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
        IAlligatorOPV4(alligator).castVoteWithReasonAndParams(authority, propId, support, reason, params);
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
        IAlligatorOPV4(alligator).castVoteWithReasonAndParamsBatched(authorities, propId, support, reason, params);
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
        IAlligatorOPV4(alligator).castVoteBySig(authority, propId, support, v, r, s);
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
        IAlligatorOPV4(alligator).castVoteWithReasonAndParamsBySig(authority, propId, support, reason, params, v, r, s);
    }
}
