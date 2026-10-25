// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornBySwarm} from "src/SwornBySwarm.sol";

/// @dev Complements the existing example tests with boundary cases, sequences and
/// metamorphic properties. No storage writes or token balance cheatcodes are used.
/// forge-config: default.fuzz.runs = 1024
contract SwornBySwarmPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    SwornBySwarm private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SwornBySwarm();
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
    }

    function test_OneSmallestUnitCanMoveDirectlyAndByAllowance() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        _approve(alice, spender, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        _send(bob, address(this), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveByExactAllowanceAndReturn() public {
        _approve(address(this), spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        _approve(alice, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OneBelowMaxAllowanceIsFinite() public {
        uint256 approval = type(uint256).max - 1;
        _approve(address(this), spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approval - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintTransfersRevertWithoutOverflowOrAllowanceLoss() public {
        uint256 maximum = type(uint256).max;
        _approve(address(this), spender, maximum);
        address[2] memory recipients = [alice, address(this)];
        for (uint256 i; i < recipients.length; ++i) {
            bytes memory errorData =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
            vm.expectRevert(errorData);
            token.transfer(recipients[i], maximum);
            vm.expectRevert(errorData);
            vm.prank(spender);
            token.transferFrom(address(this), recipients[i], maximum);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), spender), maximum);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_UnlimitedApprovalCanBeRevokedAfterUse() public {
        _approve(address(this), spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        // Revocation is not a permanent freeze: a fresh approval enables a new spend.
        _approve(address(this), spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_UnlimitedApprovalCanBeReplacedWithFiniteApproval() public {
        _approve(address(this), spender, type(uint256).max);
        _approve(address(this), spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ZeroDelegatedTransferPreservesFiniteAndUnlimitedAllowances() public {
        uint256[3] memory approvals = [uint256(1), type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            // Alice has no balance. Zero must still succeed and emit Transfer.
            _approve(alice, spender, approvals[i]);
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(alice, bob, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroSpenderCannotBeApprovedEvenForZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroSenderCannotTransferEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApproverCannotCreateAnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, type(uint256).max);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSourceCannotMintEvenForZeroAmount() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.prank(spender);
            (bool success,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), alice, amounts[i])));
            // Several preconditions are invalid; only rejection and atomicity are required.
            assertFalse(success, "transferFrom accepted the mint address as a source");
            assertEq(token.allowance(address(0), spender), 0);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_PayableCallsToTokenOperationsRevertWithoutChangingState() public {
        _approve(address(this), address(this), SUPPLY);
        vm.deal(address(this), 1);
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeCall(token.approve, (spender, 1)),
            abi.encodeCall(token.transferFrom, (address(this), alice, 1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "ERC20 operation accepted ETH");
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), spender), 0);
            assertEq(token.allowance(address(this), address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(address(token).balance, 0);
            assertEq(address(this).balance, 1);
        }
    }

    function testFuzz_ApprovalsReplaceRatherThanAccumulateAndAreIdempotent(uint256 first, uint256 second) public {
        _approve(alice, spender, first);
        assertEq(token.allowance(alice, spender), first);
        _approve(alice, spender, second);
        assertEq(token.allowance(alice, spender), second);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, second);
        _approve(alice, spender, second);
        assertEq(token.allowance(alice, spender), second);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalIsScopedToBothOwnerAndSpender(uint256 approval, uint256 rawAmount) public {
        uint256 balance = SUPPLY / 2;
        assertTrue(token.transfer(alice, balance));
        assertTrue(token.transfer(bob, balance));
        _approve(alice, spender, approval);
        _approve(bob, spender, type(uint256).max);
        _approve(alice, bob, type(uint256).max - 1);
        uint256 amount = bound(rawAmount, 0, approval < balance ? approval : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, amount));
        assertEq(token.allowance(alice, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.allowance(bob, spender), type(uint256).max);
        assertEq(token.allowance(alice, bob), type(uint256).max - 1);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), balance - amount);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.balanceOf(spender), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectRoundTripRestoresBalancesAndPreservesAllowances(uint256 rawAmount, uint256 approval)
        public
    {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        _approve(address(this), spender, approval);
        _approve(alice, spender, type(uint256).max);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        _send(alice, address(this), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplittingATransferHasTheSameResult(uint256 rawAmount, uint256 rawFirstPart) public {
        SwornBySwarm unsplit = new SwornBySwarm();
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 first = bound(rawFirstPart, 0, amount);
        assertTrue(token.transfer(alice, first));
        assertEq(token.balanceOf(alice), first);
        assertTrue(token.transfer(alice, amount - first));
        assertTrue(unsplit.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), unsplit.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), unsplit.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(unsplit.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedAndDirectTransfersAgreeForEveryActorAlias(
        uint256 rawAmount,
        uint8 ownerSeed,
        uint8 recipientSeed,
        uint8 spenderSeed,
        bool unlimited
    ) public {
        SwornBySwarm direct = new SwornBySwarm();
        address[3] memory actors = [alice, bob, spender];
        address owner = actors[ownerSeed % 3];
        address recipient = actors[recipientSeed % 3];
        address delegate = actors[spenderSeed % 3];
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(owner, SUPPLY));
        assertTrue(direct.transfer(owner, SUPPLY));
        _approve(owner, delegate, unlimited ? type(uint256).max : amount);
        vm.prank(delegate);
        assertTrue(token.transferFrom(owner, recipient, amount));
        vm.prank(owner);
        assertTrue(direct.transfer(recipient, amount));
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), direct.balanceOf(actors[i]));
        }
        assertEq(token.balanceOf(owner), owner == recipient ? SUPPLY : SUPPLY - amount);
        assertEq(token.balanceOf(recipient), owner == recipient ? SUPPLY : amount);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(owner, delegate), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(direct.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 rawBalance, uint256 rawAmount, bool unlimited)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        _approve(alice, spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approval);
        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RefillingBalanceDoesNotRestoreSpentAllowance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        _approve(address(this), spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        _send(alice, address(this), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroRecipientFailurePreservesApprovalForValidRetry(uint256 rawAmount, bool unlimited) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        _approve(address(this), spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address delegate, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(delegate, amount));
    }

    function _send(address owner, address recipient, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
    }
}
