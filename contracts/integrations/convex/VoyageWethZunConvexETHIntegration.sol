//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import 'contracts/integrations/convex/common/VoyageConvexETHPoolIntegration.sol';
import './common/ICurvePool.sol';

/// @title Voyage WETH-ZUN pool integration
contract VoyageWethZunConvexETHIntegration is VoyageConvexETHPoolIntegration {
    using SafeERC20 for IERC20;

    /// @dev Meta pool specific addresses
    address private constant WETH_ZUN_POOL =
        0x9dBcfC09E651c040EE68D6DbEB8a09F8dd0cAA77;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) VoyageConvexETHPoolIntegration(363, _oracle, _feeHandler) {}

    /// @dev query underlying tokens of the LP
    function _queryUnderlyings() internal override {
        for (uint256 i = 0; i < 2; ++i) {
            address coin = ICurve3CRVBasePool(WETH_ZUN_POOL).coins(i);
            _underlyingTokenIndex[coin] = i + 1;
            _underlyingTokens.push(coin);
        }
    }

    /// @dev deposit stablecoin to Curve LP
    function _depositStablecoin(
        uint256 _amount,
        uint256 _minLPAmount
    ) internal override {
        uint256[2] memory amounts;
        amounts[_underlyingTokenIndex[WETH_TOKEN] - 1] = _amount;

        IERC20(WETH_TOKEN).safeIncreaseAllowance(WETH_ZUN_POOL, _amount);
        ICurvePool(WETH_ZUN_POOL).add_liquidity(amounts, _minLPAmount);
    }

    /// @dev withdraw stablecoin from Curve LP
    function _withdrawStablecoin(
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal override {
        ICurvePool(WETH_ZUN_POOL).remove_liquidity_one_coin(
            _lpTokens,
            int128(int256(_underlyingTokenIndex[WETH_TOKEN] - 1)),
            _minAmount
        );
    }

    /// @dev exit LP and prepare emergency withdrawn tokens
    function _exitPoolForEmergencyWithdraw(
        uint256 _lpTokens,
        uint256[10] memory _minAmounts
    ) internal override {
        uint256 length = _underlyingTokens.length;
        uint256[] memory balanceBefore = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            balanceBefore[i] = IERC20(_underlyingTokens[i]).balanceOf(
                address(this)
            );
        }

        uint256[2] memory minAmounts;
        minAmounts[0] = _minAmounts[0];
        minAmounts[1] = _minAmounts[1];

        ICurvePool(WETH_ZUN_POOL).remove_liquidity(_lpTokens, minAmounts);

        for (uint256 i = 0; i < length; ++i) {
            emergencyWithdrawnTokens[i] =
                IERC20(_underlyingTokens[i]).balanceOf(address(this)) -
                balanceBefore[i];
        }
    }

    /// @dev swap extra rewards to USDT (reward)
    function _swapExtraRewards(
        uint256 _minAmount
    ) internal override returns (uint256) {}
}
