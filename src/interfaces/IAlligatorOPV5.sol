// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {SubdelegationRules} from "../structs/RulesV3.sol";

interface IAlligatorOPV6 {
    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function castVote(uint256 proposalId, uint8 support) external;

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason)
        external;

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    function subdelegate(address to, SubdelegationRules calldata subdelegateRules) external;

    function subdelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegateRules) external;

    function subdelegateBatched(address[] calldata targets, SubdelegationRules[] calldata subdelegationRules)
        external;
    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) external view returns (uint256);

    /**
     * @dev Returns the amount of votes that `account` had at the end of a past block (`blockNumber`).
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    function proxyAddress(address owner) external view returns (address endpoint);

    function votesCast(address proxy, uint256 proposalId, address delegator, address delegate)
        external
        view
        returns (uint256 votes);
}
