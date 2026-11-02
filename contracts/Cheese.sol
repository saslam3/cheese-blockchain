// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Cheese Supply Chain Provenance System:
 * Each cheese wheel is a unique token owned by its current custodian in the supply chain
 * Certificates and raw sensor data stay off-chain (IPFS)
 * Only hashes are stored on-chain
 */

interface ICheeseProvenance {

    // Stages of supply chain: Produced, Aging, Inspected, Shipped, Delivered
    enum Status { 
        Produced, 
        Aging, 
        Inspected, 
        Shipped, 
        Delivered 
    }

    // Register a new cheese and assign it a unique ID, only used by Producer
    function registerCheese(bytes32 originDataHash) external returns (uint256 id);

    // Move a cheese to its next stage, only used by current custodian
    function updateStatus(uint256 id, Status newStatus) external;

    // Record an inspection result and the IPFS certificate hash, only used by inspector
    function recordInspection(uint256 id, bytes32 certificateHash, bool approved) external;

    // Hand custody to the next party in supply chain, only used by current custodian
    function transferCustody(uint256 id, address to) external;

    // Called by the sensor script to record aging-room data for a cheese, only used by sensor script 
    function submitSensorReading(uint256 id, bytes32 readingsHash, bool outOfRange) external;

    // Read a cheese's current custodian and status, anyone can use
    function getCheese(uint256 id) external view returns (address custodian, Status status);
}