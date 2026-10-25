// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SwornBySwarm (SWORN)
/// @notice One billion tokens with 18 decimals, minted once to the deploying address.
/// @dev The launch factory receives the whole supply when it deploys this contract.
/// There are no administrative powers or externally accessible mint or burn functions.
contract SwornBySwarm is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("SwornBySwarm", "SWORN") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
