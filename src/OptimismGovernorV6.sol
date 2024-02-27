// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {OptimismGovernorV5} from "./OptimismGovernorV5.sol";
import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {IProposalTypesConfigurator} from "./interfaces/IProposalTypesConfigurator.sol";
import {VotingModule} from "./modules/VotingModule.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {IGovernorUpgradeable} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {IApprovalVotingModuleOld} from "./lib/internal/IApprovalVotingModuleOld.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

/**
 * Modifications from OptimismGovernorV5
 * - Adds support for partial voting, only via Alligator
 * - Adds support for votable supply oracle
 * - Adds support for proposal types
 */
contract OptimismGovernorV6 is OptimismGovernorV5 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastUpgradeable for uint256;
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant GOVERNOR_VERSION = 2;

    // Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    // TODO: Before deploying, set correct addresses
    address public constant ALLIGATOR = 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9;

    IVotableSupplyOracle public constant VOTABLE_SUPPLY_ORACLE =
        IVotableSupplyOracle(0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b);

    IProposalTypesConfigurator public constant PROPOSAL_TYPES_CONFIGURATOR =
        IProposalTypesConfigurator(0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * Total number of `votes` that `account` has cast for `proposalId`.
     * @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for partial voting.
     */
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /*//////////////////////////////////////////////////////////////
                               ALLIGATOR
    //////////////////////////////////////////////////////////////*/

    modifier onlyAlligator() {
        if (msg.sender != ALLIGATOR) revert("Unauthorized");
        _;
    }

    /**
     * @dev Count `votes` for `account` on `proposalId` and update `weightCast`.
     * Reverts if `votes` exceeds the remaining weight of `account` on `proposalId`.
     *
     * @param proposalId The id of the proposal to vote on
     * @param account The address for which to count votes for, the proxy
     * @param votes The number of votes to count
     * @param accountVotes The total number of votes delegated to `account`
     */
    function increaseWeightCast(uint256 proposalId, address account, uint256 votes, uint256 accountVotes)
        external
        onlyAlligator
    {
        require((weightCast[proposalId][account] += votes) <= accountVotes, "Governor: total weight exceeded");
    }

    /**
     * @dev Cast a vote assuming `alligator` is sending the correct voting power, has recorded weight cast
     * for proxy addresses and has done the necessary checks.
     *
     * @param proposalId The id of the proposal to vote on
     * @param voter The address who cast the vote on behalf of the proxy
     * @param support The support of the vote, `0` for against and `1` for for
     * @param reason The reason given for the vote by the voter
     * @param votes The number of votes to count
     * @param params The params for the vote
     */
    function castVoteFromAlligator(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes calldata params
    ) external onlyAlligator {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        // Skip `totalWeight` check and count `votes`
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (!proposalVote.hasVoted[voter]) {
            proposalVote.hasVoted[voter] = true;
            votes += _getVotes(voter, _proposals[proposalId].voteStart.getDeadline(), "");
        }

        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += votes;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += votes;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += votes;
        } else {
            revert("GovernorVotingSimple: invalid value for enum VoteType");
        }

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, voter, support, votes, params);
        }

        /// @dev `voter` is emitted in the event instead of `proxy`
        emit VoteCastWithParams(voter, proposalId, support, votes, reason, params);
    }

    /*//////////////////////////////////////////////////////////////
                           GOVERNOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updated version of `propose` in which `proposalType` is set and checked.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) public virtual onlyManager returns (uint256 proposalId) {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );
        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.proposalType = proposalType;

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description,
            proposalType
        );
    }

    /**
     * @dev Updated version in which `proposalType` is set and checked.
     */
    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) public virtual onlyManager returns (uint256 proposalId) {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );
        require(approvedModules[address(module)], "Governor: module not approved");

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        bytes32 descriptionHash = keccak256(bytes(description));

        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);
        proposal.proposalType = proposalType;

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(
            proposalId, _msgSender(), address(module), proposalData, snapshot, deadline, description, proposalType
        );
    }

    /**
     * Updated version in which default `proposalType` is set to 0.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        return propose(targets, values, calldatas, description, 0);
    }

    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        virtual
        override
        returns (uint256)
    {
        return proposeWithModule(module, proposalData, description, 0);
    }

    /**
     * @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
     * in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256 weight)
    {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        weight = _getVotes(account, _proposals[proposalId].voteStart.getDeadline(), "");

        _countVote(proposalId, account, support, weight, params);

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, account, support, weight, params);
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Add support for `weightCast` to check if `account` has voted on `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account)
        public
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, IGovernorUpgradeable)
        returns (bool)
    {
        return weightCast[proposalId][account] != 0 || _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Returns the votable supply for the current block number.
     */
    function votableSupply() public view virtual returns (uint256) {
        return VOTABLE_SUPPLY_ORACLE.votableSupply();
    }

    /**
     * @dev Returns the votable supply for `blockNumber`.
     */
    function votableSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return VOTABLE_SUPPLY_ORACLE.votableSupply(blockNumber);
    }

    /**
     * Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
     *
     * @dev Based on `votableSupply` by default, but falls back to `totalSupply` if not available.
     * @dev Supply is calculated at the proposal snapshot block
     * @dev Quorum value is derived from `PROPOSAL_TYPES_CONFIGURATOR`
     */
    function quorum(uint256 proposalId)
        public
        view
        virtual
        override(GovernorVotesQuorumFractionUpgradeableV2, IGovernorUpgradeable)
        returns (uint256)
    {
        uint256 snapshotBlock = proposalSnapshot(proposalId);
        uint256 supply = votableSupply(snapshotBlock);

        // Fallback to total supply if votable supply was unset at `snapshotBlock`
        if (supply == 0) {
            return token.getPastTotalSupply(snapshotBlock) * quorumNumerator(snapshotBlock) / quorumDenominator();
        }

        uint256 proposalTypeId = _proposals[proposalId].proposalType;

        return (supply * PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).quorum) / PERCENT_DIVISOR;
    }

    /**
     * Updated version in which quorum is based on `proposalId` instead of snapshot block
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /**
     * @dev Added logic based on approval voting threshold to determine if vote has succeeded.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool voteSucceeded) {
        ProposalCore storage proposal = _proposals[proposalId];

        address votingModule = proposal.votingModule;
        if (votingModule != address(0)) {
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) return false;
        }

        uint256 approvalThreshold = PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposal.proposalType).approvalThreshold;

        if (approvalThreshold == 0) return true;

        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        uint256 forVotes = proposalVote.forVotes;
        uint256 totalVotes = forVotes + proposalVote.againstVotes;

        if (totalVotes != 0) {
            voteSucceeded = (forVotes * PERCENT_DIVISOR) / totalVotes >= approvalThreshold;
        }
    }

    /**
     * @dev Allows manager to modify the proposalType of a proposal, in case it was set incorrectly.
     */
    function editProposalType(uint256 proposalId, uint8 proposalType) external onlyManager {
        if (proposalSnapshot(proposalId) == 0) revert InvalidProposalId();

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        _proposals[proposalId].proposalType = proposalType;

        emit ProposalTypeUpdated(proposalId, proposalType);
    }

    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return _proposals[proposalId].proposalType;
    }

    /**
     * Params encoding:
     * - modules = custom external params depending on module used
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Returns the current version of the governor.
     */
    function VERSION() public pure virtual returns (uint256) {
        return GOVERNOR_VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                           COMPATIBILITY FIX
    //////////////////////////////////////////////////////////////*/

    /**
     * Old modules store votes in their own storage, while new ones directly use governor state.
     *
     * In order to keep compatibility for state of old approval voting props, related votes are cloned in the governor.
     */
    function _correctStateForPreviousApprovalProposals() external reinitializer(3) {
        uint256[] memory proposalIds = new uint256[](10);
        proposalIds[0] = 102821998933460159156263544808281872605936639206851804749751748763651967264110;
        proposalIds[1] = 13644637236772462780287582686131348226526824657027343360896627559283471469688;
        proposalIds[2] = 87355419461675705865096288750937924893466943101654806912041265394266455745819;
        proposalIds[3] = 96868135958111078064987938855232246504506994378309573614627090826820561655088;
        proposalIds[4] = 16633367863894036056841722161407059007904922838583677995599242776177398115322;
        proposalIds[5] = 76298930109016961673734608568752969826843280855214969572559472848313136347131;
        proposalIds[6] = 89065519272487155253137299698235721564519179632704918690534400514930936156393;
        proposalIds[7] = 103713749716503028671815481721039004389156473487450783632177114353117435138377;
        proposalIds[8] = 33427192599934651870985988641044334656392659371327786207584390219532311772967;
        proposalIds[9] = 2803748188551238423262549847018364268422519232004056376953100549201854740200;

        IApprovalVotingModuleOld approvalModule = IApprovalVotingModuleOld(0x54A8fCBBf05ac14bEf782a2060A8C752C7CC13a5);

        for (uint256 i = 0; i < proposalIds.length; i++) {
            uint256 proposalId = proposalIds[i];
            IApprovalVotingModuleOld.ProposalVotes memory existingVotes = approvalModule._proposals(proposalId).votes;
            ProposalVote storage proposalVote = _proposalVotes[proposalId];
            proposalVote.forVotes = existingVotes.forVotes;
            proposalVote.abstainVotes = existingVotes.abstainVotes;
        }
    }
}
