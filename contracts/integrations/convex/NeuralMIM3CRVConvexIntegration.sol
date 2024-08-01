//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/convex/common/NeuralConvexPoolIntegration.sol';

/// @title Neural MIM-3CRV pool integration
contract NeuralMIM3CRVConvexIntegration is NeuralConvexPoolIntegration {
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
    ) internal override {}

    /// @dev withdraw stablecoin from Curve LP
    function _withdrawStablecoin(
        address _stablecoin,
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal override {}

    /// @dev exit LP and prepare emergency withdrawn tokens
    function _exitPoolForEmergencyWithdraw(
        uint256 _lpTokens,
        uint256[10] memory _minAmounts
    ) internal override {}

    /// @dev swap extra rewards to USDT (reward)
    function _swapExtraRewards(
        uint256 _minAmount
    ) internal override returns (uint256) {}
}
