// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AurenProtocol.sol";

contract MockFactory {
    function createPair(address, address) external pure returns (address pair) {
        return address(0x2001);
    }
}

contract MockRouter {
    function factory() external pure returns (address) {
        return address(0x1001);
    }

    function WETH() external pure returns (address) {
        return address(0x1002);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external {}

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external {}

    function addLiquidityETH(
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        return (0, 0, 0);
    }

    function addLiquidity(
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        uint256
    )
        external
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        return (0, 0, 0);
    }
}

contract TestAuren is AUREN {
    constructor(address router)
        AUREN(
            router,
            "Auren Protocol",
            "AU",
            18,
            1_000_000_000,
            msg.sender,
            msg.sender
        )
    {}
}

contract FalseReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract AurenProtocolTest is Test {
    TestAuren internal token;
    MockRouter internal router;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal spender = address(0xBEEF);

    address internal constant PAIR = address(0x2001);
    address internal constant MOCK_FACTORY = address(0x1001);

    function setUp() public {
        // MockRouter.factory() returns 0x1001.
        // Put MockFactory bytecode at that exact address.
        vm.etch(MOCK_FACTORY, type(MockFactory).runtimeCode);

        router = new MockRouter();
        token = new TestAuren(address(router));
    }

    /*
     * A normal non-whitelisted holder requesting a transfer of
     * their entire balance does NOT transfer the requested amount.
     *
     * The contract silently changes:
     *
     * amount = balance * 9999 / 10000
     */
    function testFullBalanceTransferIsSilentlyReduced() public {
        uint256 amount = 10_000 ether;

        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);

        vm.prank(alice);
        bool success = token.transfer(bob, amount);

        assertTrue(success);

        uint256 expectedTransferred = (amount * 9999) / 10000;
        uint256 expectedRemaining = amount - expectedTransferred;

        assertEq(token.balanceOf(bob), expectedTransferred);
        assertEq(token.balanceOf(alice), expectedRemaining);

        // Demonstrates that transfer() returned true even though
        // less than the requested amount was transferred.
        assertLt(token.balanceOf(bob), amount);
    }

    /*
     * transferFrom() reduces allowance by the ORIGINAL requested
     * amount even though _transfer() silently reduces the actual
     * transferred amount.
     */
    function testTransferFromConsumesFullAllowanceButTransfersLess() public {
        uint256 amount = 10_000 ether;

        token.transfer(alice, amount);

        vm.prank(alice);
        token.approve(spender, amount);

        assertEq(token.allowance(alice, spender), amount);

        vm.prank(spender);
        bool success = token.transferFrom(alice, bob, amount);

        assertTrue(success);

        uint256 actualTransferred = (amount * 9999) / 10000;
        uint256 remainingBalance = amount - actualTransferred;

        assertEq(token.balanceOf(bob), actualTransferred);
        assertEq(token.balanceOf(alice), remainingBalance);

        // Entire allowance was consumed.
        assertEq(token.allowance(alice, spender), 0);

        // But the requested amount was NOT transferred.
        assertLt(actualTransferred, amount);
    }

    /*
     * With a balance of 1 smallest token unit:
     *
     * (1 * 9999) / 10000 == 0
     *
     * transfer() succeeds but moves zero tokens.
     */
    function testDustBalanceCannotBeTransferred() public {
        token.transfer(alice, 1);

        assertEq(token.balanceOf(alice), 1);

        vm.prank(alice);
        bool success = token.transfer(bob, 1);

        assertTrue(success);

        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    /*
     * Owner can set maxTXAmount to zero.
     * This can prevent ordinary buys from the configured AMM pair.
     */
    function testOwnerCanSetMaxTxToZeroAndBlockBuy() public {
        uint256 amount = 100 ether;

        // Supply pair with tokens.
        token.transfer(PAIR, amount);

        token.startTrade();
        token.setMaxTxAmount(0);

        vm.prank(PAIR);
        vm.expectRevert("max tx amount exceeded");
        token.transfer(alice, amount);
    }

    /*
     * setFundAddress() accepts address(0).
     */
    function testFundAddressCanBeSetToZero() public {
        token.setFundAddress(address(0));

        assertEq(token.fundAddress(), address(0));
        assertTrue(token._feeWhiteList(address(0)));
    }

    /*
     * Changing fundAddress does not remove the previous address
     * from the fee whitelist.
     */
    function testOldFundAddressRemainsWhitelisted() public {
        address oldFund = token.fundAddress();
        address newFund = address(0xCAFE);

        assertTrue(token._feeWhiteList(oldFund));

        token.setFundAddress(newFund);

        assertEq(token.fundAddress(), newFund);

        // New fund is whitelisted.
        assertTrue(token._feeWhiteList(newFund));

        // Previous fund remains privileged as well.
        assertTrue(token._feeWhiteList(oldFund));
    }

    /*
     * claimToken() ignores the return value of ERC20.transfer().
     * A token can return false without reverting and claimToken()
     * will still report successful execution.
     */
    function testClaimTokenDoesNotRevertWhenTransferReturnsFalse() public {
        FalseReturnToken falseToken = new FalseReturnToken();

        falseToken.mint(address(token), 100 ether);

        assertEq(falseToken.balanceOf(address(token)), 100 ether);

        token.claimToken(
            address(falseToken),
            100 ether,
            alice
        );

        // Nothing moved.
        assertEq(falseToken.balanceOf(address(token)), 100 ether);
        assertEq(falseToken.balanceOf(alice), 0);
    }
}
