// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Just for test
contract GovernanceV2 is UUPSUpgradeable, Initializable {
    address owner;

    function initialize() public initializer {
        owner = msg.sender;
    }

    function myNumber() public pure returns (uint256) {
        return 1; // A function to test the implementation
    }
    
    function _authorizeUpgrade(address _newImplementation) internal override {}
    
    fallback() external payable {}
}