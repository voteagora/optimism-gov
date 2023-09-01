// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./setup/SetupAlligatorOPV2.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AlligatorOPV2Test is SetupAlligatorOPV2 {
    function testDeploy() public {
        assertEq(Ownable(address(alligator)).owner(), address(this));
    }

    function testCreate() public {
        address computedAddress = alligator.proxyAddress(Utils.carol, baseRulesHash);
        assertTrue(computedAddress.code.length == 0);
        alligator.create(Utils.carol, baseRules);
        assertTrue(computedAddress.code.length != 0);
    }

    function testProxyAddressMatches() public {
        address proxy = alligator.create(Utils.carol, baseRules);
        assertEq(alligator.proxyAddress(Utils.carol, baseRulesHash), proxy);
    }

    function testCastVote() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this), baseRulesHash), address(this), authority, proposalId, 1);
        alligator.castVote(baseRulesHash, authority, proposalId, 1);

        address[] memory authority2 = new address[](2);
        authority2[0] = address(Utils.alice);
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(
            alligator.proxyAddress(address(Utils.alice), baseRulesHash), address(this), authority2, proposalId, 1
        );
        alligator.castVote(baseRulesHash, authority2, proposalId, 1);
    }

    function testCastVoteWithReason() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this), baseRulesHash), address(this), authority, proposalId, 1);
        alligator.castVoteWithReason(baseRulesHash, authority, proposalId, 1, "reason");

        address[] memory authority2 = new address[](2);
        authority2[0] = address(Utils.alice);
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.alice, baseRules, address(this), subdelegationRules);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(
            alligator.proxyAddress(address(Utils.alice), baseRulesHash), address(this), authority2, proposalId, 1
        );
        alligator.castVoteWithReason(baseRulesHash, authority2, proposalId, 1, "reason");
    }

    function testCastVoteWithReasonAndParamsBatched() public {
        (address[][] memory authorities, address[] memory proxies, bytes32[] memory proxyRulesHashes) =
            _formatBatchData();

        vm.prank(Utils.carol);
        vm.expectEmit(true, true, false, true);
        emit VotesCast(proxies, Utils.carol, authorities, proposalId, 1);
        alligator.castVoteWithReasonAndParamsBatched(proxyRulesHashes, authorities, proposalId, 1, "", "");

        assertEq(governor.hasVoted(proposalId, alligator.proxyAddress(address(this), baseRulesHash)), true);
        assertEq(governor.hasVoted(proposalId, alligator.proxyAddress(Utils.bob, baseRulesHash)), true);
    }

    function _formatBatchData()
        internal
        returns (address[][] memory authorities, address[] memory proxies, bytes32[] memory proxyRulesHashes)
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

        alligator.subDelegate(address(this), baseRules, Utils.alice, subdelegationRules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, subdelegationRules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, subdelegationRules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.bob, baseRules, Utils.carol, subdelegationRules);

        proxies = new address[](2);
        proxies[0] = alligator.proxyAddress(address(this), baseRulesHash);
        proxies[1] = alligator.proxyAddress(Utils.bob, baseRulesHash);

        proxyRulesHashes = new bytes32[](2);
        proxyRulesHashes[0] = baseRulesHash;
        proxyRulesHashes[1] = baseRulesHash;
    }

    /*//////////////////////////////////////////////////////////////
                              CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Uncomment the relative version to log the calldata size of before running this function.
     * The logged calldata are those of the `castVoteWithReasonAndParamsBatched` function
     * Gas values reported are derived from the result of `getL1GasUsed` from the [GasPriceOracle contract]
     * (https://optimistic.etherscan.io/address/0x420000000000000000000000000000000000000F)
     */
    function testLogCalldataSize_CastVoteWithReasonAndParamsBatched() public view {
        uint256 proxiesNumber = 200;

        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        address[][] memory authorities = new address[][](proxiesNumber);
        bytes32[] memory baseRulesHashes = new bytes32[](proxiesNumber);
        BaseRules[] memory baseProxyRules = new BaseRules[](proxiesNumber);

        for (uint256 i = 0; i < proxiesNumber; i++) {
            authorities[i] = authority;
            baseRulesHashes[i] = bytes32(type(uint256).max);
            baseProxyRules[i] = BaseRules({
                maxRedelegations: 255,
                notValidBefore: type(uint32).max,
                notValidAfter: type(uint32).max,
                blocksBeforeVoteCloses: type(uint16).max,
                customRule: address(type(uint160).max)
            });
        }
        uint8 support = 2;
        string memory reason = "";
        bytes memory params = "";

        // Current version: 2,05k gas/proxy
        // console.logBytes(abi.encode(baseProxyRules, authorities, proposalId, support, reason, params));

        // Optimized baseRules: 1,55k gas/proxy
        // console.logBytes(abi.encode(baseRulesHashes, authorities, proposalId, support, reason, params));

        // 1 proxy per address: 1,04k gas/proxy
        // console.logBytes(abi.encode(authorities, proposalId, support, reason, params));

        // No authority chains: 523 gas/proxy
        // console.logBytes(abi.encode(baseRulesHashes, proposalId, support, reason, params));
    }

    /**
     * @dev Measure the execution cost of the `castVoteWithReasonAndParamsBatched` function for a given `proxiesNumber`
     */
    function testMeasureGas_CastVoteWithReasonAndParamsBatched() public {
        uint256 proxiesNumber = 100;

        (address[][] memory authorities, address[] memory proxies, bytes32[] memory baseRulesHashes) =
            _formatBatchDataAlt(proxiesNumber);

        uint256 propId = _propose("Alt proposal");

        console2.log("For %s proxies", proxiesNumber);
        startMeasuringGas("Measured gas cost");
        alligator.castVoteWithReasonAndParamsBatched(baseRulesHashes, authorities, propId, 1, "", "");
        stopMeasuringGas();

        for (uint256 i = 0; i < proxiesNumber; i++) {
            assertEq(governor.hasVoted(propId, proxies[i]), true);
        }
    }

    function _formatBatchDataAlt(uint256 proxiesNumber)
        internal
        returns (address[][] memory authorities, address[] memory proxies, bytes32[] memory proxyRulesHashes)
    {
        authorities = new address[][](proxiesNumber);
        proxies = new address[](proxiesNumber);
        proxyRulesHashes = new bytes32[](proxiesNumber);

        for (uint256 i = 0; i < proxiesNumber; i++) {
            // Define an owner and mint OP to it
            address proxyOwner = address(uint160(i + 1));
            vm.prank(op.owner());
            op.mint(proxyOwner, 1e20);

            // Create a proxy for the owner
            address proxyAddress = alligator.create(proxyOwner, baseRules);

            vm.startPrank(proxyOwner);

            // Delegate the owner's OP to the proxy
            op.delegate(proxyAddress);

            // Subdelegate the proxy to `address(this)`
            alligator.subDelegate(proxyOwner, baseRules, address(this), subdelegationRules);

            vm.stopPrank();

            // Define authority chain to be used by `address(this)`, ie the delegate
            address[] memory authority = new address[](2);
            authority[0] = proxyOwner;
            authority[1] = address(this);

            // Push values to the returned arrays
            authorities[i] = authority;
            proxies[i] = proxyAddress;
            proxyRulesHashes[i] = baseRulesHash;
        }
    }
}