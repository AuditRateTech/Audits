// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AurenProtocol.sol";

contract SwapMockFactory {
    function createPair(address, address) external pure returns (address pair) {
        return address(0x2001);
    }
}

contract RevertingFund {
    receive() external payable {
        revert("NO BNB");
    }
}

contract SwapMockRouter {
    uint256 public lastAmountOutMin;
    address public lastTo;
    bool public swapCalled;

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
        uint256 amountOutMin,
        address[] calldata,
        address to,
        uint256
    ) external {
        swapCalled = true;
        lastAmountOutMin = amountOutMin;
        lastTo = to;

        // Simulate PancakeSwap sending BNB to the token contract.
        (bool ok,) = payable(to).call{value: 1 ether}("");
        require(ok, "BNB SEND FAILED");
    }

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
        pure
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        return (0, 0, 0);
    }

    receive() external payable {}
}

contract SwapTestAuren is AUREN {
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

contract AurenSwapTest is Test {
    SwapTestAuren internal token;
    SwapMockRouter internal router;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    address internal constant PAIR = address(0x2001);
    address internal constant FACTORY = address(0x1001);

    function setUp() public {
        vm.etch(FACTORY, type(SwapMockFactory).runtimeCode);

        router = new SwapMockRouter();
        token = new SwapTestAuren(address(router));
        token.setFundAddress(address(0xF00D));
        // Router needs BNB so it can simulate the swap output.
        vm.deal(address(router), 100 ether);

        token.startTrade();

        // Give tokens to a normal, non-whitelisted holder.
        token.transfer(alice, 100_000 ether);
    }

    /*
     * First sell accumulates fees inside the token contract.
     * Second sell causes swapTokenForFund() to execute.
     *
     * We record the amountOutMin supplied to the router.
     */
    function testInternalSwapUsesZeroMinimumOutput() public {
        vm.prank(alice);
        token.transfer(PAIR, 10_000 ether);

        assertGt(token.balanceOf(address(token)), 0);

        vm.prank(alice);
        token.transfer(PAIR, 10_000 ether);

        assertTrue(router.swapCalled());

        // Confirms there is no slippage protection.
        assertEq(router.lastAmountOutMin(), 0);
        assertEq(router.lastTo(), address(token));
    }

    /*
     * A reverting fundAddress causes the automatic fee distribution
     * inside swapTokenForFund() to revert.
     *
     * Since this logic executes during a user's sell, that sell fails too.
     */
    function testRevertingFundAddressCanBlockSellWhenSwapTriggers() public {
        RevertingFund badFund = new RevertingFund();

        token.setFundAddress(address(badFund));

        // First sell collects fee tokens.
        vm.prank(alice);
        token.transfer(PAIR, 10_000 ether);

        assertGt(token.balanceOf(address(token)), 0);

        // Second sell triggers swap -> BNB transfer to badFund -> revert.
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(PAIR, 10_000 ether);
    }

    /*
     * Owner can designate an arbitrary address as a swap pair.
     * This changes ordinary transfers to/from that address into
     * buy/sell transactions subject to trading rules and fees.
     */
    function testOwnerCanClassifyArbitraryAddressAsSwapPair() public {
        token.setSwapPairList(bob, true);

        assertTrue(token._swapPairList(bob));

        uint256 beforeBalance = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, 1_000 ether);

        uint256 received = token.balanceOf(bob) - beforeBalance;

        // Transfer to bob is now treated as a sell and charged sell fee.
        assertLt(received, 1_000 ether);
    }

    /*
     * Owner can blacklist a holder and prevent all outgoing transfers.
     */
    function testOwnerCanFreezeHolderUsingBlacklist() public {
        token.setBlackList(alice, true);

        vm.prank(alice);
        vm.expectRevert("blackList");
        token.transfer(bob, 100 ether);
    }

    /*
     * Owner can configure buy and sell fees close to 25%.
     */
    function testOwnerCanSetFeesNearTwentyFivePercent() public {
        uint256[] memory fees = new uint256[](4);

        // buy LP + fund = 2499 basis points
        fees[0] = 0;
        fees[1] = 2499;

        // sell LP + fund = 2499 basis points
        fees[2] = 0;
        fees[3] = 2499;

        token.setFees(fees);

        assertEq(token._buyFundFee(), 2499);
        assertEq(token._sellFundFee(), 2499);
    }
}
