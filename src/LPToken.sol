// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LPToken
 * @dev Liquidity Provider Token representing user's share in the Treasury Vault
 * Minting and burning restricted to authorized contracts only
 */
contract LPToken is ERC20, Ownable {
    // ========== EVENTS ==========

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    // ========== CONSTRUCTOR ==========

    constructor() ERC20("Liquidity Provider Token", "LP") Ownable(msg.sender) {}

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @dev Mint new LP tokens to specified address
     * @param to Recipient address
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Burn LP tokens from specified address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }

    /**
     * @dev Get total token supply
     * @return Total number of LP tokens in circulation
     */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Get token balance of specified address
     * @param account Address to query balance for
     * @return Token balance of the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }
}
