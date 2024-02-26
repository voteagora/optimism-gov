// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AlligatorProxy} from "./AlligatorProxy.sol";
import {SubdelegationRules, AllowanceType} from "../structs/RulesV3.sol";
import {IAlligatorOPV5} from "../interfaces/IAlligatorOPV5.sol";
import {IRule} from "../interfaces/IRule.sol";
import {IOptimismGovernor} from "../interfaces/IOptimismGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * Liquid delegator contract for OP Governor.
 * Based on Alligator V2 (https://github.com/voteagora/liquid-delegator).
 *
 * Modifications from AlligatorOP:
 * - uses hashed proxy rules to reduce calldata size
 * - Assumes 1 proxy per owner
 * - Use proxies without deploying them
 * - Casts votes in batch directly to governor via `castVoteFromAlligator`
 * - Add alt methods to limit the sender's voting power when casting votes
 * - Upgradeable version of the contract
 * - Add castVoteBySigBatched
 */
contract AlligatorOPV5 is IAlligatorOPV5, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error LengthMismatch();
    error InvalidSignature(ECDSAUpgradeable.RecoverError recoverError);
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

    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules[] subdelegationRules);
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );

    // =============================================================
    //                           LIBRARIES
    // =============================================================

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public constant GOVERNOR = 0xcDF27F107725988f2261Ce2256bDfCdE8B382B10;
    address public constant OP_TOKEN = 0x4200000000000000000000000000000000000042;
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority)");
    bytes32 public constant BALLOT_WITHPARAMS_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority,string reason,bytes params)");
    bytes32 public constant BALLOT_WITHPARAMS_BATCHED_TYPEHASH = keccak256(
        "Ballot(uint256 proposalId,uint8 support,uint256 maxVotingPower,address[][] authorities,string reason,bytes params)"
    );

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subdelegations;

    // Subdelegation keys `from` => `to`
    mapping(address from => address[] to) public forwardSubdelegationKeys;

    // Subdelegation rules `to` => `from`
    mapping(address to => address[] from) public backwardSubdelegationKeys;

    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => uint256))) private UNUSED_SLOT;

    // Records of votes cast on `proposalId` by `delegate` with `proxy` voting power from those subdelegated by `delegator`.
    // Used to prevent double voting from the same proxy and authority chain.
    mapping(
        address proxy
            => mapping(uint256 proposalId => mapping(address delegator => mapping(address delegate => uint256)))
    ) public votesCast;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initOwner) external initializer {
        PausableUpgradeable.__Pausable_init();
        OwnableUpgradeable.__Ownable_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * Validate subdelegation rules and cast a vote on the governor.
     *
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(uint256 proposalId, uint8 support) public override whenNotPaused {
        _castVoteWithReasonAndParams(msg.sender, proposalId, support, "", "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason)
        public
        override
        whenNotPaused
    {
        _castVoteWithReasonAndParams(msg.sender, proposalId, support, reason, "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        _castVoteWithReasonAndParams(msg.sender, proposalId, support, reason, params);
    }

    /**
     * Validate subdelegation rules and cast a vote by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override whenNotPaused {
        address signatory =
            _getSignatory(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support)), v, r, s);

        _castVoteWithReasonAndParams(signatory, proposalId, support, "", "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override whenNotPaused {
        address signatory = _getSignatory(
            keccak256(
                abi.encode(
                    BALLOT_WITHPARAMS_TYPEHASH,
                    proposalId,
                    support,
                    keccak256(bytes(reason)),
                    keccak256(params)
                )
            ),
            v,
            r,
            s
        );

        _castVoteWithReasonAndParams(signatory, proposalId, support, reason, params);
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param voter The address of the voter
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if there are no votes to cast.
     */
    function _castVoteWithReasonAndParams(
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal {
        uint256 snapshotBlock = _proposalSnapshot(proposalId);
        
        // Calculate voting power
        uint256 votingPower = _getVotingPowerForVoter(voter, snapshotBlock);

        // Drain proxies
        _drainProxies(voter, votingPower);

        _castVote(voter, proposalId, support, reason, votingPower, params);
    }

    function _getVotingPowerForVoter(address voter, uint256 snapshotBlock) internal view returns(uint256 votingPower) {
        // Init voting power with the voter's proxy voting power
        votingPower = IVotes(OP_TOKEN).getPastVotes(proxyAddress(voter), snapshotBlock);

        // Step 1: Caclulate total subdlegations from voter
        // TODO: Figure out how to apply rules. Eg. maxRedelgations
        uint256 subdelegatedShares = 0;
        uint256 subdelegatedAmount = 0;
        for (uint256 i = 0; i < forwardSubdelegationKeys[sender]; ++i) {
            if (forwardSubdelegationKeys[sender][i].allowanceType == AllowanceType.Relative) {
                subdelegatedShares += forwardSubdelegationKeys[sender][i].allowance;
            } else {
                subdelegatedAmount += forwardSubdelegationKeys[sender][i].allowance;
            }
        }

        // If subdelegatedShare is greater than 100%, then voter has no remaining votingPower
        if (subdelegatedShares >= 1e5) {
            // Return direct voting power
            return IVotes(OP_TOKEN).getPastVotes(voter, snapshotBlock);
        }

        // Step 2 Calculate voting power from chains
        _buildChainsAndCalculateVotingPower(voter, ZeroAddress(), votingPower);

        // Step 3: Subtract subdelegatedAmount & subdelegatedShare from voterAllowance
        votingPower = votingPower * (1e5 - subdelegatedShares) / 1e5;
        if (votingPower < subdelegatedAmount) {
            // Return direct voting power
            return IVotes(OP_TOKEN).getPastVotes(voter, snapshotBlock);
        }

        return votingPower - subdelegatedAmount;
    }

    function _buildChainsAndCalculateVotingPower(address current, address previous, uint256 availableVotes, uint256 blockNumber) internal {

        // TODO: This function does not check for double dipping. A delegate appearing in multiple chains will have their balance counted multiple times
        // Potentially, we can
        // 1. Use a mapping to keep track of the delegates that have already been counted and then clear the mapping after the function is done
        //      - However, this would require a lot of gas & will not work for view functions
        // 2. ???


        // TODO: Check for circular delegation
        // TODO: Should we allow for circular delegation?
        // TODO: Should we limit the length of the chain?     

        // Continue building the chain recursively
        for (uint i = 0; i < backwardSubdelegationKeys[current].length; i++) {
            // Skip if subdelegation allowance is 0
            SubdelegationRules subdelegationRules = subdelegations[current][backwardSubdelegationKeys[current][i]];
            if (subdelegationRules.allowance != 0) {
                _buildChainsAndCalculateVotingPower(backwardSubdelegationKeys[current][i], current, availableVotes);
            }
        }

        // Apply rules and calculate voting power for each delegate in the chain
        if (previous != ZeroAddress()) {
            // Apply rules and calculate voting power
            SubdelegationRules previousRules = subdelegations[previous][current];
            _validateAndApplyRules(previous, previousRules, availableVotes, blockNumber);
            return;
        }  
    }

    function _validateAndApplyRules(address from, SubdelegationRules rules, uint256 balance) {
        if (rules.allowance == 0) {
            return 0;
        }

        uint265 proxyBalance = IVotes(OP_TOKEN).getPastVotes(proxyAddress(from), blockNumber);

        // Calculate `voterAllowance` based on allowance given by `from`
        return _getVoterAllowance(rules.allowanceType, rules.allowance, balance + proxyBalance);
    }

    // Draining proxies starting from the closest to the voter
    function _drainProxies(address current, uint265 remainingBalance) internal {
        if (remainingBalance == 0) {
            return;
        }

        // Check subdelegations and drain allowance
        for (uint i = 0; i < backwardSubdelegationKeys[current].length; i++) {
            // Skip if subdelegation allowance is 0
            SubdelegationRules subdelegationRules = subdelegations[current][backwardSubdelegationKeys[current][i]];
            if (subdelegationRules.allowance != 0) {
                uint256 allowance = _getVoterAllowance(subdelegationRules.allowanceType, subdelegationRules.allowance, remainingBalance);
                remainingBalance -= allowance;

                // record votes cast from proxy
                votesCast[proxy][proposalId][delegator][delegator = from] += allowance;

                _drainProxies(backwardSubdelegationKeys[current][i], remainingBalance - allowance);
            }
        }

    }

    function _recordVotesToCast(
        uint256 k,
        address proxy,
        uint256 proposalId,
        address[] memory authority,
        uint256 votesToCast,
        uint256 proxyTotalVotes
    ) internal {
        // Record weight cast for a proxy, on the governor
        IOptimismGovernor(GOVERNOR).increaseWeightCast(proposalId, proxy, votesToCast, proxyTotalVotes);

        // Record `votesToCast` across the authority chain, only for voters whose allowance does not exceed proxy
        // remaining votes. This is because it would be unnecessary to do so as if they voted they would exhaust the
        // proxy votes regardless of votes cast by their delegates.
        if (k != 0) {
            /// @dev `k - 1` cannot underflow as `k` is always greater than 0
            /// @dev cumulative votesCast cannot exceed proxy voting power, thus cannot overflow
            unchecked {
                address delegator = authority[k - 1];
                uint256 authorityLength = authority.length;

                for (k; k < authorityLength;) {
                    votesCast[proxy][proposalId][delegator][delegator = authority[k]] += votesToCast;

                    ++k;
                }
            }
        }
    }

    function _getSignatory(bytes32 structHash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (address signatory)
    {
        ECDSAUpgradeable.RecoverError recoverError;
        (signatory, recoverError) = ECDSAUpgradeable.tryRecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this))),
                    structHash
                )
            ),
            v,
            r,
            s
        );

        if (signatory == address(0)) {
            revert InvalidSignature(recoverError);
        }
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * Subdelegate `to` with `subdelegationRules`.
     * Creates a proxy for `msg.sender` if it does not exist.
     *
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subdelegate(address to, SubdelegationRules calldata subdelegationRules) public override whenNotPaused {
        subdelegations[msg.sender][to] = subdelegationRules;
        _addToSubdelegationKeys(msg.sender, to);

        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * Subdelegate `targets` with `subdelegationRules`.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        public
        override
        whenNotPaused
    {
        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subdelegations[msg.sender][targets[i]] = subdelegationRules;
            _addToSubdelegationKeys(msg.sender, targets[i]);

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    /**
     * Subdelegate `targets` with different `subdelegationRules` for each target.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateBatched(address[] calldata targets, SubdelegationRules[] calldata subdelegationRules)
        public
        override
        whenNotPaused
    {
        uint256 targetsLength = targets.length;
        if (targetsLength != subdelegationRules.length) revert LengthMismatch();

        for (uint256 i; i < targetsLength;) {
            subdelegations[msg.sender][targets[i]] = subdelegationRules[i];
            _addToSubdelegationKeys(msg.sender, targets[i]);

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    function _addToSubdelegationKeys(address from, address to) internal {
        // Check if subdelegationKeys exists to avoid duplicates
        if (backwardSubdelegationKeys[from].length == 0) {
            backwardSubdelegationKeys[from].push(to);
        } else {
            // Check if the address is already in the array
            bool found = false;
            for (uint256 i = 0; i < backwardSubdelegationKeys[from].length; i++) {
                if (backwardSubdelegationKeys[from][i] == to) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                backwardSubdelegationKeys[from].push(to);
            }
        }

        // Do the same for forwardSubdelegationKeys
        if (forwardSubdelegationKeys[to].length == 0) {
            forwardSubdelegationKeys[to].push(from);
        } else {
            bool found = false;
            for (uint256 i = 0; i < forwardSubdelegationKeys[to].length; i++) {
                if (forwardSubdelegationKeys[to][i] == from) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                forwardSubdelegationKeys[to].push(from);
            }
        }
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * Returns the current amount of votes that `account` has.
     *
     * @param account The address of the account to check
     * @param blockNumber The block number to check
     * @return The current amount of votes that `account` has
    */
    function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return _getVotingPowerForVoter(account, blockNumber);
    }

    /**
     * Returns the address of the proxy contract for a given owner.
     *
     * @param proxyOwner The owner of the proxy.
     * @return endpoint The address of the proxy.
     */
    function proxyAddress(address proxyOwner) public view override returns (address endpoint) {
        endpoint = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            bytes32(uint256(uint160(proxyOwner))), // salt
                            keccak256(abi.encodePacked(type(AlligatorProxy).creationCode, abi.encode(GOVERNOR)))
                        )
                    )
                )
            )
        );
    }

    // =============================================================
    //                   CUSTOM GOVERNOR FUNCTIONS
    // =============================================================

    /**
     * Cast a vote on the governor with reason and params.
     *
     * @param voter The address of the voter
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The params to be passed to the governor
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes memory params
    ) internal {
        IOptimismGovernor(GOVERNOR).castVoteFromAlligator(proposalId, voter, support, reason, votes, params);
    }

    /**
     * Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return endBlock Proposal's end block number
     */
    function _proposalEndBlock(uint256 proposalId) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).proposalDeadline(proposalId);
    }

    /**
     * Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @return snapshotBlock Proposal's snapshot block number
     */
    function _proposalSnapshot(uint256 proposalId) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).proposalSnapshot(proposalId);
    }

    /**
     * Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @param proxy The address of the proxy
     * @return weightCast Weight cast by the proxy
     */
    function _weightCast(uint256 proposalId, address proxy) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).weightCast(proposalId, proxy);
    }

    // =============================================================
    //                     RESTRICTED, INTERNAL
    // =============================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * Pauses and unpauses propose, vote and sign operations.
     *
     * @dev Only contract owner can toggle pause.
     */
    function _togglePause() external onlyOwner {
        if (!paused()) {
            _pause();
        } else {
            _unpause();
        }
    }

    function _validateRules(
        SubdelegationRules memory rules,
        address sender,
        uint256 authorityLength,
        uint256 proposalId,
        uint256 support,
        address from,
        address to,
        uint256 redelegationIndex
    ) internal view {
        /// @dev `maxRedelegation` cannot overflow as it increases by 1 each iteration
        /// @dev block.number + rules.blocksBeforeVoteCloses cannot overflow uint256
        unchecked {
            if (uint256(rules.maxRedelegations) + redelegationIndex < authorityLength) {
                revert TooManyRedelegations(from, to);
            }
            if (block.timestamp < rules.notValidBefore) {
                revert NotValidYet(from, to, rules.notValidBefore);
            }
            if (rules.notValidAfter != 0) {
                if (block.timestamp > rules.notValidAfter) revert NotValidAnymore(from, to, rules.notValidAfter);
            }
            if (rules.blocksBeforeVoteCloses != 0) {
                if (_proposalEndBlock(proposalId) > uint256(block.number) + uint256(rules.blocksBeforeVoteCloses)) {
                    revert TooEarly(from, to, rules.blocksBeforeVoteCloses);
                }
            }
            if (rules.customRule != address(0)) {
                if (
                    IRule(rules.customRule).validate(GOVERNOR, sender, proposalId, uint8(support))
                        != IRule.validate.selector
                ) {
                    revert InvalidCustomRule(from, to, rules.customRule);
                }
            }
        }
    }

    /**
     * Return the allowance of a voter, used in `validate`.
     */
    function _getVoterAllowance(AllowanceType allowanceType, uint256 subdelegationAllowance, uint256 delegatorAllowance)
        private
        pure
        returns (uint256)
    {
        if (allowanceType == AllowanceType.Relative) {
            return
                subdelegationAllowance >= 1e5 ? delegatorAllowance : delegatorAllowance * subdelegationAllowance / 1e5;
        }

        // else if (allowanceType == AllowanceType.Absolute)
        return delegatorAllowance > subdelegationAllowance ? subdelegationAllowance : delegatorAllowance;
    }
}
