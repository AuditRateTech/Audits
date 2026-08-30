// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/AurenProtocol.sol";

contract FuzzMockFactory {
    function createPair(address, address) external pure returns (address pair) {
        return address(0x2001);
    }
}

contract FuzzMockRouter {
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
    ) external payable returns (uint256, uint256, uint256) {
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
    ) external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }
}

contract FuzzAuren is AUREN {
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

contract AurenFuzzTest is Test {
    FuzzAuren internal token;
    FuzzMockRouter internal router;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal spender = address(0xBEEF);

    address internal constant FACTORY = address(0x1001);

    function setUp() public {
        vm.etch(FACTORY, type(FuzzMockFactory).runtimeCode);

        router = new FuzzMockRouter();
        token = new FuzzAuren(address(router));
    }

    /*
     * For a normal transfer that does not involve a swap pair,
     * sender loss must equal recipient gain.
     */
    function testFuzzTransferConservesBalance(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000 ether);

        token.transfer(alice, amount);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, amount);

        uint256 aliceAfter = token.balanceOf(alice);
        uint256 bobAfter = token.balanceOf(bob);

        uint256 senderLoss = aliceBefore - aliceAfter;
        uint256 recipientGain = bobAfter - bobBefore;

        assertEq(senderLoss, recipientGain);
    }

    /*
     * Requested full-balance transfers from non-whitelisted users
     * should expose the silent truncation behaviour across many values.
     */
    function testFuzzFullBalanceTransferIsReduced(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 2, 1_000_000 ether);

        token.transfer(alice, amount);

        vm.prank(alice);
        token.transfer(bob, amount);

        uint256 expected = (amount * 9999) / 10000;

        assertEq(token.balanceOf(bob), expected);
        assertEq(token.balanceOf(alice), amount - expected);

        assertLt(token.balanceOf(bob), amount);
    }

    /*
     * transferFrom() consumes allowance based on requested amount,
     * while the actual transfer can be silently reduced.
     */
    function testFuzzTransferFromAllowanceMismatch(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 2, 1_000_000 ether);

        token.transfer(alice, amount);

        vm.prank(alice);
        token.approve(spender, amount);

        vm.prank(spender);
        token.transferFrom(alice, bob, amount);

        uint256 actual = (amount * 9999) / 10000;

        assertEq(token.balanceOf(bob), actual);
        assertEq(token.allowance(alice, spender), 0);
        assertLt(actual, amount);
    }

    /*
     * Fees below 25% should be accepted.
     */
    function testFuzzValidFeesAccepted(
        uint16 buyLP,
        uint16 buyFund,
        uint16 sellLP,
        uint16 sellFund
    ) public {
        buyLP = uint16(bound(buyLP, 0, 2499));
        buyFund = uint16(bound(buyFund, 0, 2499));
        sellLP = uint16(bound(sellLP, 0, 2499));
        sellFund = uint16(bound(sellFund, 0, 2499));

        vm.assume(uint256(buyLP) + uint256(buyFund) < 2500);
        vm.assume(uint256(sellLP) + uint256(sellFund) < 2500);

        uint256[] memory fees = new uint256[](4);
        fees[0] = buyLP;
        fees[1] = buyFund;
        fees[2] = sellLP;
        fees[3] = sellFund;

        token.setFees(fees);

        assertEq(token._buyLPFee(), buyLP);
        assertEq(token._buyFundFee(), buyFund);
        assertEq(token._sellLPFee(), sellLP);
        assertEq(token._sellFundFee(), sellFund);
    }

    /*
     * Buy fee >= 25% must revert.
     */
    function testFuzzBuyFeeAtOrAboveTwentyFivePercentReverts(
        uint16 buyLP,
        uint16 buyFund
    ) public {
        buyLP = uint16(bound(buyLP, 0, 5000));
        buyFund = uint16(bound(buyFund, 0, 5000));

        vm.assume(uint256(buyLP) + uint256(buyFund) >= 2500);

        uint256[] memory fees = new uint256[](4);
        fees[0] = buyLP;
        fees[1] = buyFund;
        fees[2] = 0;
        fees[3] = 0;

        vm.expectRevert("Safe Alert : fee too high");
        token.setFees(fees);
    }

    /*
     * Sell fee >= 25% must revert.
     */
    function testFuzzSellFeeAtOrAboveTwentyFivePercentReverts(
        uint16 sellLP,
        uint16 sellFund
    ) public {
        sellLP = uint16(bound(sellLP, 0, 5000));
        sellFund = uint16(bound(sellFund, 0, 5000));

        vm.assume(uint256(sellLP) + uint256(sellFund) >= 2500);

        uint256[] memory fees = new uint256[](4);
        fees[0] = 0;
        fees[1] = 0;
        fees[2] = sellLP;
        fees[3] = sellFund;

        vm.expectRevert("Safe Alert : fee too high");
        token.setFees(fees);
    }
}
