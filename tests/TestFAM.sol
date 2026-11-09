// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/ERC20.sol";

/// @notice Fixed-supply classroom token for the Sepolia Family Trust project.
contract FamilyToken is ERC20 {
    constructor() ERC20("Family Test Token", "FAM") {
        _mint(msg.sender, 100_000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
