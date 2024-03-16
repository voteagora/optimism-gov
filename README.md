# Optimism Onchain Governance

## Motivation

Optimism is moving towards onchain governance. The initial version of the governance system is used for signalling purposes only and is designed to be upgraded in the future.

## Overview

The governance contract is upgradeable. The proxy is owned by the admin address, which is currently [the Optimism multisig](https://optimistic.etherscan.io/address/0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0). The admin address can upgrade the implementation to a new version, and transfer ownership to a new address.

The core governor implementation is based on [OpenZeppelin's Governor](https://docs.openzeppelin.com/contracts/4.x/api/governance).

The contract has been modified to support the following features:

- Quorum calculation includes `for`, `against`, and `abstain` votes
- When executed, proposals don't perform any onchain actions
- A special `manager` address has certain permissions (see below)

## Roles

The contracts in this repo are designed to be used by the following roles:

- **admin** is the top-level owner of the governance system. The admin address can only do the following:

  - Upgrade implementation to a new version
  - Transfer admin role to a new address (inlcuding renouncing ownership)
  - Can't have any other roles (i.e. can't be a manager and can't interact with the governance system in any other way)

- **manager** address used in day-to-day operations of the governance system. The manager address has the following permissions:

  - Create proposals
  - Mark passed proposals as executed (without performing onchain actions)
  - Update any proposal's `endBlock` (to extend the voting period)
  - Update voting delay (number of blocks before a proposal can be voted on)
  - Update voting period (number of blocks a proposal can be voted on)
  - Update proposal threshold (number of votes required to create a proposal)
  - Update quorum (number of votes required to pass a proposal, snapshotted at the time of proposal creation)

- **voter** is any address that has OP tokens delegated to it

  - Vote on proposals
  - Delegate votes to another address (via OP token contract)

## Versions

6 versions of the OP governor implementation have been deployed.

### V1

Main implementation

### V2

- Set `quorumDenominator` to 100_000

### V3

- Added manager role: `cancel` proposal

### V4

- Fixes incorrect quorum for a past block

### V5

- Added support for voting modules
  - Update OZ `Governor` storage to add `moduleAddress` in `ProposalCore` struct
  - Updated / added new functions and events in [`OptimismGovernorV5`](/src/OptimismGovernorV5.sol) to interact with external modules
  - Updated `COUNTING_MODE` to also include `params=modules`
- Added [`ApprovalVotingModule`](/src/modules/ApprovalVotingModule.sol)

### V6

- [`Governor`](/src/OptimismGovernorV6.sol)
  - Added support for external voting modules
  - Added support for partial voting via Alligator
  - Added votable supply oracle
  - Added support for proposal types
- Voting modules with partial voting support
  - [`VotingModule`](/src/modules/VotingModule.sol)
  - [`ApprovalVotingModule`](/src/modules/ApprovalVotingModule.sol)
  - [`OptimisticModule`](/src/modules/OptimisticModule.sol)
- Liquid delegation protocol [`Alligator`](/src/alligator/AlligatorOP_V5.sol)
  - Added support for partial voting and advanced delegations
- [`ProposalTypesConfigurator`](/src/ProposalTypesConfigurator.sol)
  - Allows Governor manager to add, remove and update proposal types
- [`VotableSupplyOracle`](/src/VotableSupplyOracle.sol)
  - Allows contract owner to update votable supply used by the governor

## Deployment

- [`0xcDF27F107725988f2261Ce2256bDfCdE8B382B10`](https://optimistic.etherscan.io/address/0xcdf27f107725988f2261ce2256bdfcde8b382b10) - Optimism Governor Proxy
- [`0x7f08F3095530B67CdF8466B7a923607944136Df0`](https://optimistic.etherscan.io/address/0x7f08F3095530B67CdF8466B7a923607944136Df0) - Alligator
- [`0x67ecA7B65Baf0342CE7fBf0AA15921524414C09f`](https://optimistic.etherscan.io/address/0x67ecA7B65Baf0342CE7fBf0AA15921524414C09f) - Proposal types configurator
- [`0x1b7CA7437748375302bAA8954A2447fC3FBE44CC`](https://optimistic.etherscan.io/address/0x1b7CA7437748375302bAA8954A2447fC3FBE44CC) - Votable supply oracle

## See Also

- [OPerating Manual of the Optimism Collective](https://github.com/ethereum-optimism/OPerating-manual)
- [Agora](https://twitter.com/nounsagora)

## Audits

- [Optimism Governor V5 by Zach Obront](./audits/23-05-12_zachobront.md)
- [Optimism Governor V6 by Openzeppelin](./audits/23-11-22_openzeppelin.pdf)

## Data and event interpretation guidelines

The latest versions of the governor introduced changes that may affect how clients interpret onchain functions and events. Below are some notes and suggestions on how to handle them.

### Propose with modules

`GovernorV5` introduced the `proposeWithModule` function, allowing to attach voting modules to proposals.

When a proposal with module is created, a new [`ProposalCreated`](./OptimismGovernorV5.sol#L42) event is emitted which includes the `votingModule` address and `proposalData`.

Clients are able to determine if a proposal is standard, approval voting, optimistic or else by checking the module emitted in the event, as well as use the `PROPOSAL_DATA_ENCODING` function in the module to decode `proposalData` ([see modules section for more details](#modules)).

### Modules

Agora modules adhere to the [VotingModule interface](./src/modules/VotingModule.sol).

Clients should particularly be aware of 2 functions:

- `PROPOSAL_DATA_ENCODING`: returns the expected type for the `proposalData` passed when creating a proposal. Should be used to correctly format the `proposeWithModule` function and decode the emitted `ProposalCreated` event.
- `VOTE_PARAMS_ENCODING`: returns the expected type for the `params` passed when casting a vote. Should be used to correctly format the `castVote` function and decode the emitted `VoteCast` event.

### Votes (modules)

Votes for proposals with modules may hold additional data in `params`.

Agora modules expose a read function `VOTE_PARAMS_ENCODING` that returns the expected types, which can then be used by clients to decode the `params`.

> For example [this is the encoding used by the Approval Voting module](./modules/ApprovalVotingModule.sol#L346)

See the [modules section](#modules) for more details.

### Partial delegations

`Alligator` introduced partial delegations, or `subdelegations`, as an alternative way to delegate fractional amounts of voting power to multiple delegates.

Each partial delegation emits a [`Subdelegation` or `Subdelegations`](./alligator/AlligatorOP_V5.sol#L47) event, respectively for single and batched operations. Clients should use these events to reconstruct the allowances of each address.

Each `Subdelegation` contains a `delegator`, `delegate` and [`rules`](./src/structs/RulesV3.sol).

Specifically with respect to partial delegations, `rules` contain `allowances`, which represent the maximum amount of voting power a `delegate` can use over the `delegator`'s proxy. They can be defined either in absolute or relative amounts (when relative, a value of 1e5 or higher represents 100%).

> Caveat: A delegator can subdelegate more than 100% of their voting power. Due to how alligator works, **deriving partially delegated voting power is non-trivial** so we suggest waiting for the Agora API, or ask clarification to Agora.

### Votes (partial)

Each vote cast emits a `VoteCast` or `VoteCastWithParams` event, same as with previous implementations.

Since `GovernorV6` voters can cast votes not just with their normal delegations, but also via `Alligator` contract using partial delegations. As a result clients should be aware that **multiple `VoteCast` events can be emitted for the same voter and proposal**.

### Proposal types and approval thresholds

`GovernorV6` introduced proposal types, which define quorum and approval threshold based on the type of the proposal.

Proposal types are stored in the [`ProposalTypesConfigurator`](./src/ProposalTypesConfigurator.sol) contract.

Proposal types can be tracked from `ProposalTypeSet` events or directly from the `proposalTypes(uint256 proposalTypeId)` function.

Values are scaled by 1e4, so that

- a quorum of 5100 means 51% of votable supply at the snapshot block
- an approval threshold of 7600 means at least 76% of FOR votes are required for a proposal to pass.

> Proposals by default use proposal type with id 0, currently with quorum and approval threshold at 50%.

### Quorum, onchain read function

From `GovernorV6`, quorum accepts `proposalId` as params instead of `blockNumber`.
