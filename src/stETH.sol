// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


// @notice Ownable Mintable ERC20
contract stETH is ERC20{
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }
    constructor() ERC20("stETH", "stETH") {
        owner = msg.sender;
    }
	function mint(address account, uint256 amount) external onlyOwner{
        _mint(account, amount);
    }

	function burn(address account, uint256 amount) external onlyOwner{
        _burn(account, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner{
        owner = newOwner;
    }
}