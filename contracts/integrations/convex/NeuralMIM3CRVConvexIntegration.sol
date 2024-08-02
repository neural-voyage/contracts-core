//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import 'contracts/integrations/convex/common/NeuralConvexPoolIntegration.sol';

interface ICurvePool {
    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        int128 i,
        uint256 _min_received
    ) external returns (uint256);

    function remove_liquidity(
        uint256 _burn_amount,
        uint256[2] memory _min_amounts
    ) external returns (uint256[2] memory);
}

/// @title Neural MIM-3CRV pool integration
contract NeuralMIM3CRVConvexIntegration is NeuralConvexPoolIntegration {
    using SafeERC20 for IERC20;

    /// @dev Meta pool specific addresses
    address private constant MIM_3CRV_POOL =
        0x5a6A4D54456819380173272A5E8E9B9904BdF41B;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) NeuralConvexPoolIntegration(40, _oracle, _feeHandler) {}

    /// @dev query underlying tokens of the LP
    function _queryUnderlyings() internal override {
        for (uint256 i = 0; i < 2; ++i) {
            address coin = ICurve3CRVBasePool(MIM_3CRV_POOL).coins(i);
            _underlyingTokenIndex[coin] = i + 1;
            _underlyingTokens.push(coin);
        }
    }

    /// @dev deposit stablecoin to Curve LP
    function _depositStablecoin(
        address _stablecoin,
        uint256 _amount,
        uint256 _minLPAmount
    ) internal override {
        uint256[2] memory amounts;
        amounts[_underlyingTokenIndex[_stablecoin] - 1] = _amount;

        IERC20(_stablecoin).safeIncreaseAllowance(MIM_3CRV_POOL, _amount);
        ICurvePool(MIM_3CRV_POOL).add_liquidity(amounts, _minLPAmount);
    }

    /// @dev withdraw stablecoin from Curve LP
    function _withdrawStablecoin(
        address _stablecoin,
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal override {
        ICurvePool(MIM_3CRV_POOL).remove_liquidity_one_coin(
            _lpTokens,
            int128(int256(_underlyingTokenIndex[_stablecoin] - 1)),
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

        ICurvePool(MIM_3CRV_POOL).remove_liquidity(_lpTokens, minAmounts);

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
