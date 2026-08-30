// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";

contract FeeMathTest is Test {

    function testFuzzSwapFeeMath(
        uint128 rawTokenAmount,
        uint16 buyLP,
        uint16 buyFund,
        uint16 sellLP,
        uint16 sellFund
    ) public pure {

        uint256 tokenAmount =
            bound(uint256(rawTokenAmount), 1e9, 1_000_000 ether);

        buyLP = uint16(bound(buyLP, 0, 2499));
        buyFund = uint16(bound(buyFund, 0, 2499));
        sellLP = uint16(bound(sellLP, 0, 2499));
        sellFund = uint16(bound(sellFund, 0, 2499));

        vm.assume(uint256(buyLP) + uint256(buyFund) < 2500);
        vm.assume(uint256(sellLP) + uint256(sellFund) < 2500);

        uint256 originalSwapFee =
            uint256(buyFund) +
            uint256(buyLP) +
            uint256(sellFund) +
            uint256(sellLP);

        // swapTokenForFund() is only called when swapFee > 0
        vm.assume(originalSwapFee > 0);

        uint256 swapFee = originalSwapFee;

        // Exact contract logic
        swapFee += swapFee;

        uint256 lpFee =
            uint256(sellLP) + uint256(buyLP);

        uint256 lpAmount =
            (tokenAmount * lpFee) / swapFee;

        assertLe(lpAmount, tokenAmount);

        uint256 tokensSwapped =
            tokenAmount - lpAmount;

        assertLe(tokensSwapped, tokenAmount);

        swapFee -= lpFee;

        // Denominator used by fundAmount/lpBNB must never be zero.
        assertGt(swapFee, 0);

        // Accounting invariant.
        assertEq(tokensSwapped + lpAmount, tokenAmount);
    }
}
