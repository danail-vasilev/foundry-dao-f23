// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGoverner.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    TimeLock timeLock;
    GovToken govToken;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_AMOUNT = 100 ether;
    uint256 public constant MIN_DELAY = 3600; // 1 hour delay after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a voting is active
    uint256 public constant VOTING_PERIOD = 50400;

    // Anyone can propose and execute
    address[] public proposers;
    address[] public executors;
    uint256[] public values;
    bytes[] public calldatas;
    address[] public targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_AMOUNT);

        vm.prank(USER);
        govToken.delegate(USER);
        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, USER); // the user no longer be the admin
        vm.stopPrank();

        box = new Box();
        // transfer ownership of the box to the timeLock; TimeLock is owned by the DAO and
        // DAO owns the TimeLock but the TimeLock says where stuff goes.
        box.transferOwnership(address(timeLock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the state
        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "my reason";

        uint8 voteWay = 1; // VoteType.for - yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(box.getNumber(), valueToStore);
    }
}
