// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Proxy} from "./Proxy.sol";
import {ProxyRules, SubdelegationRules} from "../structs/RulesV2.sol";
import {IAlligatorOP} from "../interfaces/IAlligatorOP.sol";
import {IRule} from "../interfaces/IRule.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @notice Liquid delegator contract for OP Governor, based on Alligator V2 (https://github.com/voteagora/liquid-delegator).
 */
abstract contract AlligatorOP is IAlligatorOP, Ownable, Pausable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error BadSignature();
    error NotDelegated(address from, address to);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);
    error AlreadyVoted(address voter, uint256 proposalId);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event ProxyDeployed(address indexed owner, ProxyRules proxyRules, address proxy);
    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event SubDelegationProxy(
        address indexed proxy, address indexed from, address indexed to, SubdelegationRules subdelegationRules
    );
    event SubDelegationProxies(
        address indexed proxy, address indexed from, address[] to, SubdelegationRules subdelegationRules
    );
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public immutable governor;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subDelegations;

    // Subdelegation rules `from` => `to`, for a specific proxy
    mapping(address proxy => mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)))
        public subDelegationsProxy;

    // Records if a voter has already voted on a specific proposal from a proxy
    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => bool hasVoted))) hasVoted;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(address _governor, address _initOwner) {
        governor = _governor;
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    /**
     * @notice Deploy a new Proxy for an owner deterministically.
     *
     * @param owner The owner of the Proxy.
     * @param proxyRules The base rules of the Proxy.
     *
     * @return endpoint Address of the Proxy
     */
    function create(address owner, ProxyRules calldata proxyRules) public override returns (address endpoint) {
        endpoint = address(
            new Proxy{salt: bytes32(uint256(uint160(owner)))}(
                governor,
                proxyRules.maxRedelegations,
                proxyRules.notValidBefore,
                proxyRules.notValidAfter,
                proxyRules.blocksBeforeVoteCloses,
                proxyRules.customRule
            )
        );
        emit ProxyDeployed(owner, proxyRules, endpoint);
    }

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules and cast a vote on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVote(ProxyRules calldata proxyRules, address[] calldata authority, uint256 proposalId, uint8 support)
        external
        override
        whenNotPaused
    {
        address proxy = validate(proxyRules, msg.sender, authority, proposalId, support);

        // TODO: Format partial votes + append voter
        bytes memory votes;
        _castVote(proxy, msg.sender, proposalId, support, votes);

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReason(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public override whenNotPaused {
        address proxy = validate(proxyRules, msg.sender, authority, proposalId, support);

        // TODO: Format partial votes + append voter
        bytes memory votes;
        _castVoteWithReasonAndParams(proxy, msg.sender, proposalId, support, reason, votes);

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParams(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public override whenNotPaused {
        address proxy = validate(proxyRules, msg.sender, authority, proposalId, support);

        // TODO: Format partial votes + append voter
        bytes memory votes;
        _castVoteWithReasonAndParams(proxy, msg.sender, proposalId, support, reason, votes);

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
     *
     * @param proxyRules The base rules of the Proxies to vote from.
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBatched(
        ProxyRules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public override whenNotPaused {
        uint256 authorityLength = authorities.length;
        require(authorityLength == proxyRules.length);

        address[] memory proxies = new address[](authorityLength);
        address[] memory authority;
        ProxyRules memory rules;

        for (uint256 i; i < authorityLength;) {
            authority = authorities[i];
            rules = proxyRules[i];
            proxies[i] = validate(rules, msg.sender, authority, proposalId, support);

            // TODO: Format partial votes + append voter
            bytes memory votes;
            _castVoteWithReasonAndParams(proxies[i], msg.sender, proposalId, support, reason, votes);

            unchecked {
                ++i;
            }
        }

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote by signature on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteBySig(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        if (signatory == address(0)) {
            revert BadSignature();
        }

        address proxy = validate(proxyRules, signatory, authority, proposalId, support);

        // TODO: Format partial votes + append voter
        bytes memory votes;
        _castVote(proxy, signatory, proposalId, support, votes);

        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBySig(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this)));
        bytes32 structHash =
            keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, keccak256(bytes(reason)), keccak256(params)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        if (signatory == address(0)) {
            revert BadSignature();
        }

        address proxy = validate(proxyRules, signatory, authority, proposalId, support);

        // TODO: Format partial votes + append voter
        bytes memory votes;
        _castVoteWithReasonAndParams(proxy, signatory, proposalId, support, reason, votes);

        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * @notice Subdelegate all sender Proxies to an address with rules.
     *
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subDelegateAll(address to, SubdelegationRules calldata subdelegationRules) external override {
        subDelegations[msg.sender][to] = subdelegationRules;
        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate all sender Proxies to multiple addresses with rules.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subDelegateAllBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        external
        override
    {
        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subDelegations[msg.sender][targets[i]] = subdelegationRules;

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    /**
     * @notice Subdelegate one Proxy to an address with rules.
     * Creates a Proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the Proxy to sign from.
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subDelegate(
        address proxyOwner,
        ProxyRules calldata proxyRules,
        address to,
        SubdelegationRules calldata subdelegationRules
    ) external override {
        address proxy = proxyAddress(proxyOwner, proxyRules);
        if (proxy.code.length == 0) {
            create(proxyOwner, proxyRules);
        }

        subDelegationsProxy[proxy][msg.sender][to] = subdelegationRules;
        emit SubDelegationProxy(proxy, msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate one Proxy to multiple addresses with rules.
     * Creates a Proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the Proxy to sign from.
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subDelegateBatched(
        address proxyOwner,
        ProxyRules calldata proxyRules,
        address[] calldata targets,
        SubdelegationRules calldata subdelegationRules
    ) external override {
        address proxy = proxyAddress(proxyOwner, proxyRules);
        if (proxy.code.length == 0) {
            create(proxyOwner, proxyRules);
        }

        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subDelegationsProxy[proxy][msg.sender][targets[i]] = subdelegationRules;

            unchecked {
                ++i;
            }
        }

        emit SubDelegationProxies(proxy, msg.sender, targets, subdelegationRules);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules. Proxy-specific delegations override address-specific delegations.
     *
     * @param proxyRules The base rules of the Proxy.
     * @param sender The sender address to validate.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal for which validation is being performed.
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain, 0xFF=proposal
     */
    function validate(
        ProxyRules memory proxyRules,
        address sender,
        address[] memory authority,
        uint256 proposalId,
        uint256 support
    ) public view override returns (address proxy) {
        uint256 authorityLength = authority.length;

        // Validate base proxy rules
        _validateRules(proxyRules, sender, authorityLength, proposalId, support, address(0), address(0), 1);

        proxy = proxyAddress(authority[0], proxyRules);
        address from = authority[0];

        if (from == sender) {
            return proxy;
        }

        address to;
        SubdelegationRules memory subdelegationRules;
        for (uint256 i = 1; i < authorityLength;) {
            to = authority[i];
            // Retrieve proxy-specific rules
            subdelegationRules = subDelegationsProxy[proxy][from][to];
            // If a subdelegation is not present, retrieve address-specific rules
            // TODO: Check fix
            // if (subdelegationRules.permissions == 0) subdelegationRules = subDelegations[from][to];

            unchecked {
                // Validate subdelegation rules
                _validateSubdelegationRules(
                    subdelegationRules,
                    sender,
                    authorityLength,
                    proposalId,
                    support,
                    from,
                    to,
                    ++i // pass `i + 1` and increment at the same time
                );
            }

            from = to;
        }

        if (from != sender) revert NotDelegated(from, sender);
    }

    /**
     * @notice Returns the address of the proxy contract for a given owner.
     *
     * @param owner The owner of the Proxy.
     * @param proxyRules The base rules of the Proxy.
     *
     * @return endpoint The address of the Proxy.
     */
    function proxyAddress(address owner, ProxyRules memory proxyRules)
        public
        view
        override
        returns (address endpoint)
    {
        endpoint = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            bytes32(uint256(uint160(owner))), // salt
                            keccak256(
                                abi.encodePacked(
                                    type(Proxy).creationCode,
                                    abi.encode(
                                        governor,
                                        proxyRules.maxRedelegations,
                                        proxyRules.notValidBefore,
                                        proxyRules.notValidAfter,
                                        proxyRules.blocksBeforeVoteCloses,
                                        proxyRules.customRule
                                    )
                                )
                            )
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
     * @notice Cast a vote on the governor.
     *
     * @param proxy The address of the Proxy
     * @param voter The address of the voter
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param params The params to be passed to the governor
     */
    function _castVote(address proxy, address voter, uint256 proposalId, uint8 support, bytes memory params) internal {
        _recordVote(proxy, proposalId, voter);
        IGovernor(proxy).castVoteWithReasonAndParams(proposalId, support, "", params);
    }

    /**
     * @notice Cast a vote on the governor with reason.
     *
     * @param proxy The address of the Proxy
     * @param voter The address of the voter
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The params to be passed to the governor
     */
    function _castVoteWithReasonAndParams(
        address proxy,
        address voter,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) internal {
        _recordVote(proxy, proposalId, voter);
        IGovernor(proxy).castVoteWithReasonAndParams(proposalId, support, reason, params);
    }

    /**
     * @notice Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return endBlock Proposal's end block number
     */
    function _proposalEndBlock(uint256 proposalId) internal view returns (uint256 endBlock) {
        return IGovernor(governor).proposalDeadline(proposalId);
    }

    // =============================================================
    //                     RESTRICTED, INTERNAL
    // =============================================================

    /**
     * @notice Pauses and unpauses propose, vote and sign operations.
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

    function _recordVote(address proxy, uint256 proposalId, address voter) internal {
        if (hasVoted[proxy][proposalId][voter]) revert AlreadyVoted(voter, proposalId);
        hasVoted[proxy][proposalId][voter] = true;
    }

    function _validateRules(
        ProxyRules memory rules,
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
            // TODO: Check condition
            // if ((rules.permissions & permissions) != permissions) {
            //     revert NotDelegated(from, to, permissions);
            // }
            if (rules.maxRedelegations + redelegationIndex < authorityLength) {
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
                    IRule(rules.customRule).validate(governor, sender, proposalId, uint8(support))
                        != IRule.validate.selector
                ) {
                    revert InvalidCustomRule(from, to, rules.customRule);
                }
            }
        }
    }

    function _validateSubdelegationRules(
        SubdelegationRules memory rules,
        address sender,
        uint256 authorityLength,
        uint256 proposalId,
        uint256 support,
        address from,
        address to,
        uint256 redelegationIndex
    ) private view {
        _validateRules(
            ProxyRules(
                rules.maxRedelegations,
                rules.notValidBefore,
                rules.notValidAfter,
                rules.blocksBeforeVoteCloses,
                rules.customRule
            ),
            sender,
            authorityLength,
            proposalId,
            support,
            from,
            to,
            redelegationIndex
        );

        // TODO: Add allowance conditions
    }
}

// REARCHITECTURE PLAN
// - Enforce flexible voting on castVote -> castVoteWithReasonAndParams
// - Change authority chain into storage state?

// - A delegates 100 OP to A proxy (or someone else's proxy)
// - A subdelegates 10 OP to B and infiniteOP to C
// - When B votes with A power:
//   - Check voting power of proxy at proposal snapshot block, and store it for future usage
//   - CastVoteWithParams from proxy with flexible voting 10 OP