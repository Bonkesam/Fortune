// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorTimelockControl
{
    using SafeCast for uint256;

    uint256 public constant QUORUM_NUMERATOR = 400; // 4%
    uint256 public constant PROPOSAL_THRESHOLD = 1e18;

    address public immutable lotteryManager;
    address public immutable prizePool;

    error InvalidTarget();
    error UnauthorizedFunction();
    error InsufficientVotingPower();

    constructor(
        ERC20Votes _token,
        TimelockController _timelock,
        address _lotteryManager,
        address _prizePool
    )
        Governor("dFortune DAO Governor")
        GovernorSettings(
            1 /* voting delay */,
            259200 /* voting period */,
            1e18 /* proposal threshold */
        )
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
    {
        lotteryManager = _lotteryManager;
        prizePool = _prizePool;
    }

    ////////////////////////////
    /// Core Configuration /////
    ////////////////////////////

    function quorum(uint256 timepoint) public view override returns (uint256) {
        return
            (token().getPastTotalSupply(timepoint) * QUORUM_NUMERATOR) / 10000;
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    // Fix for OZ v5 compatibility
    function proposalNeedsQueuing(
        uint256 proposalId
    )
        public
        view
        virtual
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return true;
    }

    ////////////////////////////
    /// Proposal Validation ////
    ////////////////////////////

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _validateProposal(targets, calldatas);
        return super.propose(targets, values, calldatas, description);
    }

    function _validateProposal(
        address[] memory targets,
        bytes[] memory calldatas
    ) internal view {
        if (getVotes(msg.sender, clock() - 1) < proposalThreshold()) {
            revert InsufficientVotingPower();
        }

        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] != lotteryManager && targets[i] != prizePool) {
                revert InvalidTarget();
            }

            // Fixed the bytes4 selector extraction
            bytes memory calldata_i = calldatas[i];
            bytes4 selector;
            assembly {
                // OZ v5 compatibility fix - ensure proper selector extraction
                selector := mload(add(calldata_i, 32))
            }

            if (!_isAllowedFunction(selector)) {
                revert UnauthorizedFunction();
            }
        }
    }

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

    ////////////////////////////
    /// Voting Configuration ///
    ////////////////////////////

    // For OZ v5, adjust quorum settings to ensure proposals can pass
    // Override votingDelay and votingPeriod for complete clarity
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    // Override for the counting mode to ensure OZ v5 compatibility
    function COUNTING_MODE()
        public
        pure
        override(IGovernor, GovernorCountingSimple)
        returns (string memory)
    {
        return "support=bravo&quorum=for,abstain";
    }

    ////////////////////////////
    /// Timelock Integration ///
    ////////////////////////////

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return
            GovernorTimelockControl._queueOperations(
                proposalId,
                targets,
                values,
                calldatas,
                descriptionHash
            );
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        GovernorTimelockControl._executeOperations(
            proposalId,
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    //////////////////////////////
    /// Required Overrides ///////
    //////////////////////////////

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

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    //////////////////////////////
    /// Clock Configuration //////
    //////////////////////////////

    function clock()
        public
        view
        override(Governor, GovernorVotes)
        returns (uint48)
    {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE()
        public
        pure
        override(Governor, GovernorVotes)
        returns (string memory)
    {
        return "mode=timestamp";
    }
}
