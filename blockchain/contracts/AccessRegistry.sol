// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AccessRegistry {
    address public owner;
    mapping(address => bool) public allowed;

    event AccessChanged(address indexed wallet, bool authorized, uint256 timestamp);

    constructor() {
        owner = msg.sender;
    }

    function setAccess(address wallet, bool authorized) external {
        require(msg.sender == owner, "only owner");
        allowed[wallet] = authorized;
        emit AccessChanged(wallet, authorized, block.timestamp);
    }
}
