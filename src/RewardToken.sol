// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardToken is ERC20, Ownable {
    error NotMinter();

    mapping(address => bool) public minters;

    constructor() ERC20("Reward Token", "RWD") Ownable(msg.sender) {}

    function setMinter(address account, bool enabled) external onlyOwner {
        minters[account] = enabled;
    }

    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }
}
