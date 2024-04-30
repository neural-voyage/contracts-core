//SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title Stablz token
contract Stablz is ERC20Burnable {

    constructor () ERC20("Stablz", "STABLZ") {
        _mint(msg.sender, 100_000_000 * (10 ** decimals()));
    }
}
