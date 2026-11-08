// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MSMELedger
 * @dev Milestone 1 — Scaffolding placeholder contract.
 *      This contract exists only to validate that the Hardhat
 *      compilation pipeline is correctly configured.
 *
 *      Application-specific contracts (DeliveryOrder, DeliveryReceipt,
 *      AcceptanceRecord, etc.) will be implemented in future milestones.
 */
contract MSMELedger {
    string public constant PROJECT = "MSME Delivery & Acceptance Ledger";
    string public constant VERSION = "0.1.0";

    event Initialized(address indexed deployer, uint256 timestamp);

    constructor() {
        emit Initialized(msg.sender, block.timestamp);
    }
}
