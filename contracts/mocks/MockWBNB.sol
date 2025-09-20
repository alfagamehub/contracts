// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockERC20.sol";

/// @title MockWBNB
/// @notice Minimal WBNB wrapper with deposit/withdraw for tests.
contract MockWBNB is MockERC20 {
    constructor() MockERC20("Wrapped BNB (Mock)", "WBNB", 18) {}

    /// @notice Wrap native BNB to WBNB 1:1
    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @notice Unwrap WBNB back to native BNB
    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "BAL_LOW");
        _burn(msg.sender, wad);
        (bool ok,) = msg.sender.call{value: wad}("");
        require(ok, "SEND_FAIL");
    }

    // internal mint/burn using inherited storage
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}