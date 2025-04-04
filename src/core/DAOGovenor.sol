// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title dFortune DAO Governor
 * @notice Governance contract for protocol parameter management
 * @dev Combines OZ Governor with timelock and vote delegation
 * Features:
 * - Proposal threshold
 * - Voting delay/period
 * - Timelock execution
 * - Quorum management
 */
contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorVotes,
    GovernorTimelockControl
{
    using SafeCast for uint256;

    /// @notice Minimum quorum numerator (basis points of total supply)
    uint256 public constant QUORUM_NUMERATOR = 400; // 4%

    /// @notice Minimum voting power needed to create proposal
    uint256 public constant PROPOSAL_THRESHOLD = 1e18; // 1 FORT

    /// @notice Supported contract targets for governance
    address public immutable lotteryManager;
    address public immutable prizePool;

    /// @notice Track proposal validation status
    mapping(uint256 => bool) private _validProposals;

    /// @dev Custom errors for gas efficiency
    error InvalidTarget();
    error UnauthorizedFunction();
    error InsufficientVotingPower();
    error AlreadyValidated();

    constructor(
        IVotes _token,
        TimelockController _timelock,
        address _lotteryManager,
        address _prizePool
    )
        Governor("dFortune DAO Governor")
        GovernorSettings(
            1 /* 1 block voting delay */,
            45818 /* ~7 days (12s/block) */,
            1e18 /* proposal threshold */
        )
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
    {
        lotteryManager = _lotteryManager;
        prizePool = _prizePool;
    }

    /**
     * @notice Create a new governance proposal
     * @param targets Contract addresses to call
     * @param values ETH values for calls
     * @param calldatas Encoded function calls
     * @param description Proposal description
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _validateProposal(targets, calldatas);
        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @notice Validate proposal targets and functions
     * @dev Only allows modifying LotteryManager or PrizePool
     */
    function _validateProposal(
        address[] memory targets,
        bytes[] memory calldatas
    ) internal {
        if (getVotes(msg.sender, block.number - 1) < proposalThreshold()) {
            revert InsufficientVotingPower();
        }

        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] != lotteryManager && targets[i] != prizePool) {
                revert InvalidTarget();
            }

            bytes4 selector = bytes4(calldatas[i][:4]);
            if (!_isAllowedFunction(selector)) {
                revert UnauthorizedFunction();
            }
        }
    }

    /**
     * @notice Check if function selector is governance-allowed
     */
    function _isAllowedFunction(bytes4 selector) internal pure returns (bool) {
        return
            selector == bytes4(keccak256("setTicketPrice(uint256)")) ||
            selector ==
            bytes4(
                keccak256("updatePrizeDistribution(uint256,uint256,uint256)")
            ) ||
            selector == bytes4(keccak256("setProtocolFee(uint256)")) ||
            selector ==
            bytes4(keccak256("setYieldProtocol(address,address,bool)"));
    }

    /**
     * @notice Current quorum requirement
     * @param blockNumber Block number to check quorum at
     * @return quorum Required number of votes
     */
    function quorum(
        uint256 blockNumber
    ) public view override returns (uint256) {
        return
            (token.getPastTotalSupply(blockNumber) * QUORUM_NUMERATOR) / 10000;
    }

    /**
     * @notice Get voting delay
     * @dev Overrides both Governor and GovernorSettings
     */
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    /**
     * @notice Get voting period
     * @dev Overrides both Governor and GovernorSettings
     */
    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    /**
     * @notice Get proposal threshold
     * @dev Overrides both Governor and GovernorSettings
     */
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /**
     * @notice Get Governor compatibility
     */
    function state(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /**
     * @notice Create timelock execution
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancel timelock execution
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Get executor address
     */
    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
