# bondcurve-v1

EVM network smart contracts for the HippoxOS bond curve system.

## Overview

hippox-bond-curve-v1 provides the on-chain bond curve mechanism for the HippoxOS ecosystem, enabling programmatic pricing and issuance of bonds based on a predefined curve.

## Core Features

- Bond Curve Pricing: Bond prices are determined by a mathematical curve tied to supply or other on-chain parameters.
- Bond Issuance: Supports minting and redeeming bonds according to the curve logic.
- On-chain Settlement: All pricing, issuance, and redemption are executed transparently on-chain.

## Project Structure

src/ Core bond curve contracts
test/ Tests
script/ Deployment and interaction scripts

## Development

Build: forge build
Test: forge test
Local node: anvil
Deploy: forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
