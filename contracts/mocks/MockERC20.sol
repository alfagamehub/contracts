// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockERC20
/// @notice Simple mintable/burnable ERC20 for testing with configurable decimals.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8  public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Initializes the token after code injection (constructor-less).
    /// @dev Can only be called once; sets name, symbol, decimals.
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _decimals Token decimals
    function initialize(string memory _name, string memory _symbol, uint8 _decimals) public {
        require(bytes(name).length == 0 && bytes(symbol).length == 0, "Already initialized");
        name = _name;
        symbol = _symbol;
        assembly { sstore(decimals.slot, _decimals) }
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "BAL_LOW");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "BAL_LOW");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}