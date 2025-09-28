// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing using OpenZeppelin's ERC20 implementation
 */
contract MockERC20 is ERC20 {
    uint8 private _tokenDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        _tokenDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
