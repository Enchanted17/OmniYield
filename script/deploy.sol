// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/OmniYieldPortal.sol";

contract DeployOmniYield is Script {
    OmniYieldPortal public portal;
    GovernanceToken public gt;
    LPToken public lp;
    TreasuryVault public tv;
    Governance public gov;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying OmniYield Protocol...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the main portal (deploys all sub-contracts)
        portal = new OmniYieldPortal();

        // Fetch deployed instances
        gt = portal.gt();
        lp = portal.lp();
        tv = portal.tv();
        gov = portal.gov();

        vm.stopBroadcast();

        // Log all addresses
        console.log("");
        console.log("Deployment Complete!");
        console.log("-----------------------------------");
        console.log("OmniYieldPortal:  ", address(portal));
        console.log("GovernanceToken:  ", address(gt));
        console.log("LPToken:          ", address(lp));
        console.log("TreasuryVault:    ", address(tv));
        console.log("Governance:       ", address(gov));
        console.log("-----------------------------------");
        console.log("");
        console.log("Next steps:");
        console.log("1. Transfer ownership to multisig/DAO:");
        console.log("   cast send <PORTAL> \"transferOwnership(address)\" <MULTISIG>");
        console.log("2. Verify contracts on Etherscan/Blockscan:");
        console.log("   forge verify-contract ...");
    }
}
