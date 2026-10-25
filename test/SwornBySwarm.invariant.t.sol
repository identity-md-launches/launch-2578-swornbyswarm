// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornBySwarm} from "../src/SwornBySwarm.sol";

/// @dev Test-only state machine. Only these four actors may receive tokens, so their
/// balances form a closed system. Expected balances/allowances are maintained independently.
contract SwornHandler is Test {
    SwornBySwarm public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SwornBySwarm token_) {
        token = token_;
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 available = expectedBalance[from];
        uint256 amount = _amountAtBoundary(rawAmount, available);
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, amount <= available, "transfer result differs from ledger");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, available, amount)
            );
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        uint256 available = balance < approved ? balance : approved;
        uint256 amount = _amountAtBoundary(rawAmount, available);
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, amount <= available, "transferFrom result differs from ledger");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        } else if (amount > approved) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
    }

    /// @dev Deliberately switches between revoked, dust, finite and unlimited approvals.
    /// Random uint256 approvals alone rarely exercise these state transitions.
    function approveAtBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256[5] memory values = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        uint256 amount = values[mode % values.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Prepares no new approval: the zero-recipient rejection must roll back whatever
    /// allowance the preceding random sequence left, including a finite allowance decrement.
    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 available = expectedBalance[owner];
        uint256 approved = expectedAllowance[owner][spender];
        if (delegated && approved < available) available = approved;
        uint256 amount = bound(rawAmount, 0, available);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        vm.prank(delegated ? spender : owner);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "zero recipient accepted");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        // No ghost update: both invariants must still match the state before this call.
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        vm.prank(owner);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "zero spender accepted");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    /// @dev Selecting a funded holder ensures every call exercises a positive transfer.
    /// Any holder must be able to move its entire balance, including after rejected calls.
    function transferFullBalance(uint256 ownerSeed, uint256 recipientSeed) external {
        uint256 index = ownerSeed % 4;
        for (uint256 i; expectedBalance[actors[index]] == 0 && i < 4; ++i) {
            index = (index + 1) % 4;
        }
        address owner = actors[index];
        address recipient = actors[(index + 1 + recipientSeed % 3) % 4];
        uint256 amount = expectedBalance[owner];
        assertGt(amount, 0, "closed ledger has no funded holder");
        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[owner] = 0;
        expectedBalance[recipient] += amount;
        assertEq(token.balanceOf(owner), 0, "holder cannot empty balance");
    }

    function _amountAtBoundary(uint256 rawAmount, uint256 available) private pure returns (uint256) {
        uint256 mode = rawAmount % 7;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return available;
        // available never exceeds the fixed supply, so this cannot overflow.
        if (mode == 3) return available + 1;
        if (mode == 4) return type(uint256).max;
        if (mode == 5) return bound(rawAmount, 0, available);
        return rawAmount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract SwornBySwarmInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    SwornBySwarm private token;
    SwornHandler private handler;

    function setUp() public {
        token = new SwornBySwarm();
        handler = new SwornHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = SwornHandler.transfer.selector;
        selectors[1] = SwornHandler.approve.selector;
        selectors[2] = SwornHandler.transferFrom.selector;
        selectors[3] = SwornHandler.approveAtBoundary.selector;
        selectors[4] = SwornHandler.rejectZeroRecipient.selector;
        selectors[5] = SwornHandler.rejectZeroSpender.selector;
        selectors[6] = SwornHandler.transferFullBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndAllBalancesAreAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "SwornBySwarm");
        assertEq(token.symbol(), "SWORN");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
