// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockTicketNFT
 * @dev Mock implementation of TicketNFT for testing purposes
 */
contract MockTicketNFT is Ownable {
    // State variables
    address public lotteryManager;
    bool public mintBatchCalled;
    address public lastMintTo;
    uint256 public lastMintQuantity;
    uint256 public lastMintDrawId;

    // Mapping for ticket owners
    mapping(uint256 => address) private _ticketOwners;

    // Array to hold minted ticket IDs for testing
    uint256[] private _nextTicketIds;

    constructor(address initialOwner) Ownable(initialOwner) {}

    // Setup function for tests
    function setLotteryManager(address _lotteryManager) external onlyOwner {
        lotteryManager = _lotteryManager;
    }

    // Setup function for tests
    function setNextTicketIds(uint256[] memory ticketIds) external {
        delete _nextTicketIds;
        for (uint256 i = 0; i < ticketIds.length; i++) {
            _nextTicketIds.push(ticketIds[i]);
        }
    }

    // Setup function for tests
    function setTicketOwner(uint256 tokenId, address owner) external {
        _ticketOwners[tokenId] = owner;
    }

    /**
     * @notice Mock minting function
     * @param to Address to mint tickets to
     * @param quantity Number of tickets to mint
     * @param drawId Draw ID these tickets are for
     * @return ticketIds Array of minted ticket IDs
     */
    function mintBatch(
        address to,
        uint256 quantity,
        uint256 drawId
    ) external returns (uint256[] memory) {
        // Only the lottery manager can mint tickets
        require(msg.sender == lotteryManager, "Not lottery manager");

        // Set test variables for verification
        mintBatchCalled = true;
        lastMintTo = to;
        lastMintQuantity = quantity;
        lastMintDrawId = drawId;

        // Return the pre-configured ticket IDs
        require(_nextTicketIds.length >= quantity, "Not enough ticket IDs");

        uint256[] memory ticketIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            ticketIds[i] = _nextTicketIds[i];
            _ticketOwners[_nextTicketIds[i]] = to; // Set the owner
        }

        return ticketIds;
    }

    /**
     * @notice Mock function to get owner of a ticket
     * @param tokenId Token ID to check
     * @return Owner address
     */
    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _ticketOwners[tokenId];
        require(owner != address(0), "Token does not exist");
        return owner;
    }

    /**
     * @notice Mock function to burn a ticket
     * @param tokenId Token ID to burn
     */
    function burn(uint256 tokenId) external {
        require(_ticketOwners[tokenId] != address(0), "Token does not exist");
        _ticketOwners[tokenId] = address(0);
    }

    /**
     * @notice Mock function for getting ticket draw ID
     * @param tokenId The token ID to query
     * @return Draw ID
     */
    function getTicketDrawId(uint256 tokenId) external view returns (uint256) {
        return 0; // Simplistic implementation, can be enhanced if needed
    }
}
