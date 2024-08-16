//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import 'contracts/integrations/aerodrome/common/IVeloRouter.sol';
import 'contracts/integrations/aerodrome/common/IVeloFactory.sol';
import 'contracts/integrations/aerodrome/common/IVeloPair.sol';
import 'contracts/integrations/aerodrome/common/NeuralAerodromeETHPoolIntegration.sol';

/// @title Neural DOLA-USDC pool integration
contract NeuralWethRethAerodromeIntegration is
    NeuralAerodromeETHPoolIntegration
{
    using SafeERC20 for IERC20;

    /// @dev pool specific addresses
    address private constant WETH_rETH =
        0xb8866732424AcDdd729C6fcf7146b19bFE4A2e36;
    address private constant WETH_rETH_GAUGE =
        0xAa3D51d36BfE7C5C63299AF71bc19988BdBa0A06;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    )
        NeuralAerodromeETHPoolIntegration(
            WETH_rETH,
            WETH_rETH_GAUGE,
            _oracle,
            _feeHandler
        )
    {}

    /// @notice Calculates the optimal amount of TokenA to swap to TokenB
    ///         for a perfect LP deposit for a stable pair.
    /// @param factory The Velodrome factory address.
    /// @param lpToken The Velodrome lp token address.
    /// @param amount0 The amount of `token0` this vault has currently.
    /// @param reserve0 The amount of `token0` the LP has in reserve.
    /// @param reserve1 The amount of `token1` the LP has in reserve.
    /// @param decimals0 The decimals of `token0`.
    /// @param decimals1 The decimals of `token1`.
    /// @return The optimal amount of TokenA to swap.
    function _optimalDeposit(
        address factory,
        address lpToken,
        uint256 amount0,
        uint256 reserve0,
        uint256 reserve1,
        uint256 decimals0,
        uint256 decimals1
    ) internal view returns (uint256) {
        // Cache swap fee from pair factory.
        uint256 swapFee = IVeloFactory(factory).getFee(lpToken, true);
        uint256 a;

        // sAMM deposit calculation.
        a = (((amount0 * 10000) / (10000 - swapFee)) * 1e18) / decimals0;

        uint256 x = (reserve0 * 1e18) / decimals0;
        uint256 y = (reserve1 * 1e18) / decimals1;
        uint256 x2 = (x * x) / 1e18;
        uint256 y2 = (y * y) / 1e18;
        uint256 p = (y * (((x2 * 3 + y2) * 1e18) / (y2 * 3 + x2))) / x;

        uint256 num = a * y;
        uint256 den = ((a + x) * p) / 1e18 + y;

        return ((num / den) * decimals0) / 1e18;
    }

    /// @dev deposit stablecoin to Curve LP
    function _depositStablecoin(
        uint256 _amount,
        uint256 _minLPAmount
    ) internal override {
        IERC20(WETH_TOKEN).safeIncreaseAllowance(AERODROME_ROUTER, _amount);

        (uint256 r0, uint256 r1, ) = IVeloPair(AERODROME_LP_TOKEN)
            .getReserves();
        (uint256 reserveA, uint256 reserveB) = WETH_TOKEN ==
            _underlyingTokens[0]
            ? (r0, r1)
            : (r1, r0);
        (address tokenA, address tokenB) = WETH_TOKEN == _underlyingTokens[0]
            ? (_underlyingTokens[0], _underlyingTokens[1])
            : (_underlyingTokens[1], _underlyingTokens[0]);

        uint256 swapAmount = _optimalDeposit(
            AERODROME_FACTORY,
            AERODROME_LP_TOKEN,
            _amount,
            reserveA,
            reserveB,
            IERC20Metadata(tokenA).decimals(),
            IERC20Metadata(tokenB).decimals()
        );

        IVeloRouter.Zap memory zapInPool;
        zapInPool.tokenA = tokenA;
        zapInPool.tokenB = tokenB;
        zapInPool.stable = true;
        zapInPool.factory = AERODROME_FACTORY;
        zapInPool.amountOutMinA = 0;
        zapInPool.amountOutMinB = 0;
        zapInPool.amountAMin = 0;
        zapInPool.amountBMin = 0;
        IVeloRouter.Route[] memory routesA = new IVeloRouter.Route[](0);
        IVeloRouter.Route[] memory routesB = new IVeloRouter.Route[](1);
        routesB[0].factory = AERODROME_FACTORY;
        routesB[0].from = tokenA;
        routesB[0].to = tokenB;
        routesB[0].stable = true;

        IVeloRouter(AERODROME_ROUTER).zapIn(
            WETH_TOKEN,
            _amount - swapAmount,
            swapAmount,
            zapInPool,
            routesA,
            routesB,
            address(this),
            false
        );

        require(
            IERC20(AERODROME_LP_TOKEN).balanceOf(address(this)) >= _minLPAmount,
            'NeuralDolaUsdcAerodromeIntegration: Not enough result'
        );
    }

    /// @dev withdraw stablecoin from Aerodrome
    function _withdrawStablecoin(
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal override {
        IVeloRouter(AERODROME_ROUTER).removeLiquidity(
            _underlyingTokens[0],
            _underlyingTokens[1],
            true,
            _lpTokens,
            0,
            0,
            address(this),
            block.timestamp
        );

        (address tokenA, address tokenB) = WETH_TOKEN == _underlyingTokens[0]
            ? (_underlyingTokens[0], _underlyingTokens[1])
            : (_underlyingTokens[1], _underlyingTokens[0]);

        uint256 swapAmount = IERC20(tokenB).balanceOf(address(this));
        IERC20(tokenB).safeIncreaseAllowance(AERODROME_ROUTER, swapAmount);

        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = tokenB;
        routes[0].to = tokenA;
        routes[0].stable = true;
        routes[0].factory = IVeloPool(AERODROME_LP_TOKEN).factory();

        // Swap `tokenIn` into `tokenOut`.
        IVeloRouter(AERODROME_ROUTER).swapExactTokensForTokens(
            swapAmount,
            0,
            routes,
            address(this),
            block.timestamp
        );
        require(
            IERC20(WETH_TOKEN).balanceOf(address(this)) >= _minAmount,
            'NeuralWethRethAerodromeIntegration: Not enough result'
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

        IVeloRouter(AERODROME_ROUTER).removeLiquidity(
            _underlyingTokens[0],
            _underlyingTokens[1],
            true,
            _lpTokens,
            _minAmounts[0],
            _minAmounts[1],
            address(this),
            block.timestamp
        );

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
