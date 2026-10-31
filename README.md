# Blockchain-Based Cheese Supply Chain Provenance System

## Team
Abe Troop, Eeman Huda, Josh Ebe, Parthib Faruk, and Saimah Aslam

## About
Our project tracks cheese from the producer to the store using blockchain. Each cheese wheel will have a unique token, and registered participants will record ownership transfers, inspections, and status updates. Consumers will scan a QR code to view its history.

Basic records and document hashes will be stored on-chain, while larger files will be stored in IPFS. The system still relies on participants providing accurate information.

## Planned Tools
Solidity, Hardhat, Node.js, npm, OpenZeppelin, IPFS, and a browser wallet. We plan to demo on Sepolia and explore Polygon for lower fees.

## Setup
The repository currently contains a draft contract interface. Once the Hardhat configuration and dependency files are added

## Usage and Deployment
Producers will register cheese wheels, holders will transfer ownership, and inspectors will record inspection results. A simulation script will submit aging-room readings, and a web page will show the history.

We will test locally before deploying to Sepolia. Deployment instructions will be added later.

## Current Files
- `README.md`: project overview and planned setup

The contract implementation, tests, IPFS connection, simulation, and web page are still planned.
