// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./setup/SetupAlligatorOP.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlligatorOP} from "src/alligator/AlligatorOP.sol";
import {GovernorCountingSimpleUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";

contract AlligatorOPTest is SetupAlligatorOP {
    function setUp() public virtual override {
        SetupAlligatorOP.setUp();

        alligatorAlt = address(new AlligatorOP(address(governor), address(op), address(this)));
        vm.etch(alligator, alligatorAlt.code);

        proxy1 = _create(address(this), baseRules, baseRulesHash);
        proxy2 = _create(Utils.alice, baseRules, baseRulesHash);
        proxy3 = _create(Utils.bob, baseRules, baseRulesHash);

        _postSetup();
    }

    function testDeploy() public virtual {
        assertEq(Ownable(address(alligatorAlt)).owner(), address(this));
    }

    function testCreate() public virtual {
        address computedAddress = _proxyAddress(Utils.carol, baseRules, baseRulesHash);
        assertTrue(computedAddress.code.length == 0);
        _create(Utils.carol, baseRules, baseRulesHash);
        assertTrue(computedAddress.code.length != 0);
    }

    function testProxyAddressMatches() public virtual {
        address proxy = _proxyAddress(Utils.carol, baseRules, baseRulesHash);
        assertEq(_create(Utils.carol, baseRules, baseRulesHash), proxy);
    }

    function testCastVote() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        standardCastVote(authority);

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.alice;
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        standardCastVote(authority2);
    }

    function testCastVoteWithReason() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        standardCastVoteWithReason(authority, "reason");

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.alice;
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        standardCastVoteWithReason(authority2, "reason");
    }

    function testCastVoteWithReasonAndParams() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        standardCastVoteWithReasonAndParams(authority, "reason", "params");

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.alice;
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        standardCastVoteWithReasonAndParams(authority2, "reason", "params");
    }

    function testCastVoteWithReasonAndParamsBatched() public virtual {
        (
            address[][] memory authorities,
            address[] memory proxies,
            BaseRules[] memory proxyRules,
            bytes32[] memory proxyRulesHashes
        ) = _formatBatchData();

        standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, "reason", "params"
        );

        for (uint256 i = 0; i < proxies.length; i++) {
            assertEq(governor.hasVoted(proposalId, proxies[i]), true);
        }
    }

    function testCastVoteBySig() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = signer;

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, signer, subdelegationRules);

        standardCastVoteBySig(authority);
    }

    function testCastVoteWithReasonAndParamsBySig() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = signer;

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, signer, subdelegationRules);

        standardCastVoteWithReasonAndParamsBySig(authority);
    }

    function testSubdelegate() public virtual {
        _subdelegate(address(this), baseRules, Utils.alice, subdelegationRules);

        (BaseRules memory baseRulesSet, AllowanceType allowanceType, uint256 allowance) = AlligatorOP(alligator)
            .subdelegationsProxy(_proxyAddress(address(this), baseRules, baseRulesHash), address(this), Utils.alice);

        subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
    }

    function testSubdelegateBatched() public virtual {
        address[] memory targets = new address[](2);
        targets[0] = Utils.bob;
        targets[1] = Utils.alice;

        _subdelegateBatched(address(this), baseRules, targets, subdelegationRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (BaseRules memory baseRulesSet, AllowanceType allowanceType, uint256 allowance) = AlligatorOP(alligator)
                .subdelegationsProxy(_proxyAddress(address(this), baseRules, baseRulesHash), address(this), targets[i]);

            subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
        }
    }

    function subdelegateAssertions(
        BaseRules memory baseRulesSet,
        AllowanceType allowanceType,
        uint256 allowance,
        SubdelegationRules memory subRules
    ) internal virtual {
        assertEq(baseRulesSet.maxRedelegations, subRules.baseRules.maxRedelegations);
        assertEq(baseRulesSet.notValidBefore, subRules.baseRules.notValidBefore);
        assertEq(baseRulesSet.notValidAfter, subRules.baseRules.notValidAfter);
        assertEq(baseRulesSet.blocksBeforeVoteCloses, subRules.baseRules.blocksBeforeVoteCloses);
        assertEq(baseRulesSet.customRule, subRules.baseRules.customRule);
        assertEq(uint8(allowanceType), uint8(subRules.allowanceType));
        assertEq(allowance, subRules.allowance);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_castVote_ZeroVotesToCast() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        standardCastVote(authority);

        vm.expectRevert(ZeroVotesToCast.selector);
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
        vm.expectRevert(ZeroVotesToCast.selector);
        _castVoteWithReason(baseRules, baseRulesHash, authority, proposalId, 1, "reason");
        vm.expectRevert(ZeroVotesToCast.selector);
        _castVoteWithReasonAndParams(baseRules, baseRulesHash, authority, proposalId, 1, "reason", "params");
    }

    function testRevert_castVoteBatched_ZeroVotesToCast() public virtual {
        (
            address[][] memory authorities,
            address[] memory proxies,
            BaseRules[] memory proxyRules,
            bytes32[] memory proxyRulesHashes
        ) = _formatBatchData();

        standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, "reason", "params"
        );

        vm.expectRevert(ZeroVotesToCast.selector);
        vm.prank(Utils.carol);
        _castVoteWithReasonAndParamsBatched(
            proxyRules, proxyRulesHashes, authorities, proposalId, 1, "reason", "params"
        );
    }

    function testRevert_validate_notDelegated() public {
        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = address(this);

        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, Utils.alice, address(this)));
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function testRevert_validate_senderNotAuthorityLeaf() public {
        address[] memory authority = new address[](3);
        authority[0] = Utils.alice;
        authority[1] = Utils.bob;
        authority[2] = address(this);

        _subdelegate(Utils.alice, baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        vm.prank(Utils.bob);
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), Utils.bob));
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function testRevert_validate_delegationRevoked() public {
        SubdelegationRules memory subRules = subdelegationRules;
        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = address(this);

        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subRules);

        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);

        subRules.allowance = 0;
        vm.prank(Utils.alice);
        _subdelegate(Utils.alice, baseRules, address(this), subRules);

        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, Utils.alice, address(this)));
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function testRevert_validate_TooManyRedelegations() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        SubdelegationRules memory rules = subdelegationRules;
        rules.baseRules.maxRedelegations = 1;

        _subdelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        rules.baseRules.maxRedelegations = 255;
        _subdelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        _subdelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.carol);
        vm.expectRevert(abi.encodeWithSelector(TooManyRedelegations.selector, address(this), Utils.alice));
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);

        address[] memory authority2 = new address[](3);
        authority2[0] = address(this);
        authority2[1] = Utils.alice;
        authority2[2] = Utils.bob;

        vm.prank(Utils.bob);
        _castVote(baseRules, baseRulesHash, authority2, proposalId, 1);
    }

    function testRevert_validate_NotValidYet() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        SubdelegationRules memory rules = subdelegationRules;
        rules.baseRules.notValidBefore = uint32(block.timestamp + 1e3);

        _subdelegate(address(this), baseRules, Utils.alice, rules);

        vm.prank(Utils.alice);
        vm.expectRevert(
            abi.encodeWithSelector(NotValidYet.selector, address(this), Utils.alice, rules.baseRules.notValidBefore)
        );
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function testRevert_validate_NotValidAnymore() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        SubdelegationRules memory rules = subdelegationRules;
        rules.baseRules.notValidAfter = 90;

        _subdelegate(address(this), baseRules, Utils.alice, rules);

        vm.warp(100);
        vm.prank(Utils.alice);
        vm.expectRevert(
            abi.encodeWithSelector(NotValidAnymore.selector, address(this), Utils.alice, rules.baseRules.notValidAfter)
        );
        _castVote(baseRules, baseRulesHash, authority, 1, 1);
    }

    function testRevert_validate_TooEarly() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        SubdelegationRules memory rules = subdelegationRules;
        rules.baseRules.blocksBeforeVoteCloses = 99;

        _subdelegate(address(this), baseRules, Utils.alice, rules);

        vm.prank(Utils.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TooEarly.selector, address(this), Utils.alice, rules.baseRules.blocksBeforeVoteCloses
            )
        );
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function testRevert_togglePause_notOwner() public {
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        AlligatorOP(alligator)._togglePause();
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _proxyAddress(address proxyOwner, BaseRules memory rules, bytes32)
        internal
        view
        virtual
        returns (address computedAddress)
    {
        return AlligatorOP(alligator).proxyAddress(proxyOwner, rules);
    }

    function _create(address proxyOwner, BaseRules memory rules, bytes32)
        internal
        virtual
        returns (address computedAddress)
    {
        return AlligatorOP(alligator).create(proxyOwner, rules);
    }

    function _subdelegate(
        address proxyOwner,
        BaseRules memory rules,
        address to,
        SubdelegationRules memory subdelegateRules
    ) internal virtual {
        AlligatorOP(alligator).subdelegate(proxyOwner, rules, to, subdelegateRules);
    }

    function _subdelegateBatched(
        address proxyOwner,
        BaseRules memory rules,
        address[] memory targets,
        SubdelegationRules memory subdelegateRules
    ) internal virtual {
        AlligatorOP(alligator).subdelegateBatched(proxyOwner, rules, targets, subdelegateRules);
    }

    function _castVote(BaseRules memory rules, bytes32, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
    {
        AlligatorOP(alligator).castVote(rules, authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory rules,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual {
        AlligatorOP(alligator).castVoteWithReason(rules, authority, propId, support, reason);
    }

    function _castVoteWithReasonAndParams(
        BaseRules memory rules,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        AlligatorOP(alligator).castVoteWithReasonAndParams(rules, authority, propId, support, reason, params);
    }

    function _castVoteWithReasonAndParamsBatched(
        BaseRules[] memory rules,
        bytes32[] memory,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        AlligatorOP(alligator).castVoteWithReasonAndParamsBatched(rules, authorities, propId, support, reason, params);
    }

    function _castVoteBySig(
        BaseRules memory rules,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual {
        AlligatorOP(alligator).castVoteBySig(rules, authority, propId, support, v, r, s);
    }

    function _castVoteWithReasonAndParamsBySig(
        BaseRules memory rules,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual {
        AlligatorOP(alligator).castVoteWithReasonAndParamsBySig(
            rules, authority, propId, support, reason, params, v, r, s
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function standardCastVote(address[] memory authority) public virtual {
        vm.expectEmit();
        emit VoteCast(
            _proxyAddress(authority[0], baseRules, baseRulesHash),
            authority[authority.length - 1],
            authority,
            proposalId,
            1
        );
        _castVote(baseRules, baseRulesHash, authority, proposalId, 1);
    }

    function standardCastVoteWithReason(address[] memory authority, string memory reason) public virtual {
        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), address(this), authority, proposalId, 1);
        _castVoteWithReason(baseRules, baseRulesHash, authority, proposalId, 1, reason);
    }

    function standardCastVoteWithReasonAndParams(address[] memory authority, string memory reason, bytes memory params)
        public
        virtual
    {
        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), address(this), authority, proposalId, 1);
        _castVoteWithReasonAndParams(baseRules, baseRulesHash, authority, proposalId, 1, reason, params);
    }

    function standardCastVoteWithReasonAndParamsBatched(
        address[][] memory authorities,
        address[] memory proxies,
        BaseRules[] memory proxyRules,
        bytes32[] memory proxyRulesHashes,
        string memory reason,
        bytes memory params
    ) public virtual {
        vm.prank(Utils.carol);

        vm.expectEmit();
        emit VotesCast(proxies, Utils.carol, authorities, proposalId, 1);
        _castVoteWithReasonAndParamsBatched(proxyRules, proxyRulesHashes, authorities, proposalId, 1, reason, params);
    }

    function standardCastVoteBySig(address[] memory authority) public virtual {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, 1));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(vm.envUint("SIGNER_KEY"), keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), signer, authority, proposalId, 1);
        _castVoteBySig(baseRules, baseRulesHash, authority, proposalId, 1, v, r, s);
    }

    function standardCastVoteWithReasonAndParamsBySig(address[] memory authority) public virtual {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash =
            keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, 1, keccak256(bytes("reason")), keccak256("params")));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(vm.envUint("SIGNER_KEY"), keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0], baseRules, baseRulesHash), signer, authority, proposalId, 1);
        _castVoteWithReasonAndParamsBySig(
            baseRules, baseRulesHash, authority, proposalId, 1, "reason", "params", v, r, s
        );
    }

    function _formatBatchData()
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            BaseRules[] memory proxyRules,
            bytes32[] memory proxyRulesHashes
        )
    {
        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = Utils.carol;

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        _subdelegate(address(this), baseRules, Utils.alice, subdelegationRules);
        vm.prank(Utils.alice);
        _subdelegate(address(this), baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(address(this), baseRules, Utils.carol, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(Utils.bob, baseRules, Utils.carol, subdelegationRules);

        proxies = new address[](2);
        proxies[0] = _proxyAddress(address(this), baseRules, baseRulesHash);
        proxies[1] = _proxyAddress(Utils.bob, baseRules, baseRulesHash);

        proxyRules = new BaseRules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        proxyRulesHashes = new bytes32[](2);
        proxyRulesHashes[0] = baseRulesHash;
        proxyRulesHashes[1] = baseRulesHash;
    }

    function _formatBatchDataSigner()
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            BaseRules[] memory proxyRules,
            bytes32[] memory proxyRulesHashes
        )
    {
        (authorities, proxies, proxyRules, proxyRulesHashes) = _formatBatchData();
        authorities[0][3] = signer;
        authorities[1][1] = signer;

        vm.prank(Utils.bob);
        _subdelegate(address(this), baseRules, signer, subdelegationRules);
        vm.prank(Utils.bob);
        _subdelegate(Utils.bob, baseRules, signer, subdelegationRules);
    }

    function _formatBatchDataAlt(uint256 proxiesNumber)
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            BaseRules[] memory proxyRules,
            bytes32[] memory proxyRulesHashes
        )
    {
        authorities = new address[][](proxiesNumber);
        proxies = new address[](proxiesNumber);
        proxyRules = new BaseRules[](proxiesNumber);
        proxyRulesHashes = new bytes32[](proxiesNumber);

        for (uint256 i = 0; i < proxiesNumber; i++) {
            // Define an owner and mint OP to it
            address proxyOwner = address(uint160(i + 1));
            vm.prank(op.owner());
            op.mint(proxyOwner, 1e20);

            // Create a proxy for the owner
            address proxyAddress = _create(proxyOwner, baseRules, baseRulesHash);

            vm.startPrank(proxyOwner);

            // Delegate the owner's OP to the proxy
            op.delegate(proxyAddress);

            // Subdelegate the proxy to `address(this)`
            _subdelegate(proxyOwner, baseRules, address(this), subdelegationRules);

            vm.stopPrank();

            // Define authority chain to be used by `address(this)`, ie the delegate
            address[] memory authority = new address[](2);
            authority[0] = proxyOwner;
            authority[1] = address(this);

            // Push values to the returned arrays
            authorities[i] = authority;
            proxies[i] = proxyAddress;
            proxyRules[i] = baseRules;
            proxyRulesHashes[i] = baseRulesHash;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    // /**
    //  * @dev Uncomment the relative version to log the calldata size of before running this function.
    //  * The logged calldata are those of the `castVoteWithReasonAndParamsBatched` function
    //  * Gas values reported are derived from the result of `getL1GasUsed` from the [GasPriceOracle contract]
    //  * (https://optimistic.etherscan.io/address/0x420000000000000000000000000000000000000F)
    //  */
    // function testLogCalldataSize_CastVoteWithReasonAndParamsBatched() public view virtual {
    //     uint256 proxiesNumber = 200;

    //     address[] memory authority = new address[](2);
    //     authority[0] = address(this);
    //     authority[1] = Utils.alice;

    //     address[][] memory authorities = new address[][](proxiesNumber);
    //     bytes32[] memory baseRulesHashes = new bytes32[](proxiesNumber);
    //     BaseRules[] memory baseProxyRules = new BaseRules[](proxiesNumber);

    //     for (uint256 i = 0; i < proxiesNumber; i++) {
    //         authorities[i] = authority;
    //         baseRulesHashes[i] = bytes32(type(uint256).max);
    //         baseProxyRules[i] = BaseRules({
    //             maxRedelegations: 255,
    //             notValidBefore: type(uint32).max,
    //             notValidAfter: type(uint32).max,
    //             blocksBeforeVoteCloses: type(uint16).max,
    //             customRule: address(type(uint160).max)
    //         });
    //     }

    //     // uint8 support = 2;
    //     // string memory reason = "";
    //     // bytes memory params = "";

    //     // Current version: 2,05k gas/proxy
    //     // console.logBytes(abi.encode(baseProxyRules, authorities, proposalId, support, reason, params));

    //     // Optimized baseRules: 1,55k gas/proxy
    //     // console.logBytes(abi.encode(baseRulesHashes, authorities, proposalId, support, reason, params));

    //     // 1 proxy per address: 1,04k gas/proxy
    //     // console.logBytes(abi.encode(authorities, proposalId, support, reason, params));

    //     // No authority chains: 523 gas/proxy
    //     // console.logBytes(abi.encode(baseRulesHashes, proposalId, support, reason, params));
    // }

    // /**
    //  * @dev Measure the execution cost of the `castVoteWithReasonAndParamsBatched` function for a given `proxiesNumber`
    //  */
    // function testMeasureGas_CastVoteWithReasonAndParamsBatched() public virtual {
    //     uint256 proxiesNumber = 100;

    //     (
    //         address[][] memory authorities,
    //         address[] memory proxies,
    //         BaseRules[] memory proxyRules,
    //         bytes32[] memory proxyRulesHashes
    //     ) = _formatBatchDataAlt(proxiesNumber);

    //     uint256 propId = _propose("Alt proposal");

    //     console2.log("For %s proxies", proxiesNumber);
    //     startMeasuringGas("Measured gas cost");
    //     _castVoteWithReasonAndParamsBatched(proxyRules, proxyRulesHashes, authorities, propId, 1, "reason", "");
    //     stopMeasuringGas();

    //     for (uint256 i = 0; i < proxiesNumber; i++) {
    //         assertEq(governor.hasVoted(propId, proxies[i]), true);
    //     }
    // }
}
