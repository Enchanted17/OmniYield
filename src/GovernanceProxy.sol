// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GovernanceProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data) payable ERC1967Proxy(_implementation, _data) {}
}
