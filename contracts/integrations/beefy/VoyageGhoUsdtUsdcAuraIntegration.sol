//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/integrations/beefy/common/VoyageBeefyPoolIntegration.sol';
import 'contracts/integrations/aura/common/IBalancerVault.sol';
import 'contracts/integrations/aura/common/IBalancerPool.sol';

/// @title Voyage GHO/USDT/USDC Aura integration
contract VoyageGhoUsdtUsdcAuraIntegration is VoyageBeefyPoolIntegration {
    using SafeERC20 for IERC20;

    /// @dev LP configurations
    address internal constant VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 internal BALANCER_POOL_ID; // Balancer Pool ID

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    )
        VoyageBeefyPoolIntegration(
            0x234Fd76985dA4fD505DbAF7A48e119Cd5dFD5C8F,
            _oracle,
            _feeHandler
        )
    {}

    /// @dev query underlying tokens of the LP
    function _queryUnderlyings() internal override {
        BALANCER_POOL_ID = IBalancerPool(BEEFY_WANT).getPoolId();

        (address[] memory tokens, , ) = IBalancerVault(VAULT).getPoolTokens(
            BALANCER_POOL_ID
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            _underlyingTokenIndex[tokens[i]] = i + 1;
            _underlyingTokens.push(tokens[i]);
        }
    }

    /// @dev Deposit stablecoins
    /// @param _stablecoin stablecoin to deposit
    /// @param _amount amount to deposit
    /// @param _minLPAmount minimum amount of LP to receive
    /// @return lpTokens Amount of LP tokens received from depositing
    function _addLiquidityWithStablecoin(
        address _stablecoin,
        uint _amount,
        uint _minLPAmount
    ) internal override returns (uint256 lpTokens) {
        uint256 balanceBefore = IERC20(BEEFY_WANT).balanceOf(address(this));

        IERC20(_stablecoin).safeIncreaseAllowance(VAULT, _amount);
        IBalancerVault.JoinPoolRequest memory request;
        request.assets = _underlyingTokens;
        request.maxAmountsIn = new uint256[](request.assets.length);
        request.maxAmountsIn[_underlyingTokenIndex[_stablecoin] - 1] = _amount;
        request.userData = abi.encode(1, request.maxAmountsIn, _minLPAmount); // EXACT_TOKENS_IN_FOR_BPT_OUT
        IBalancerVault(VAULT).joinPool(
            BALANCER_POOL_ID,
            address(this),
            address(this),
            request
        );

        lpTokens = IERC20(BEEFY_WANT).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev Withdraw stablecoins
    /// @param _stablecoin chosen stablecoin to withdraw
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _removeLiquidityToStablecoin(
        address _stablecoin,
        uint _lpTokens,
        uint _minAmount
    ) internal override returns (uint256 received) {
        uint256 balanceBefore = IERC20(_stablecoin).balanceOf(address(this));

        IBalancerVault.ExitPoolRequest memory request;
        request.assets = _underlyingTokens;
        request.minAmountsOut = new uint256[](request.assets.length);
        request.minAmountsOut[
            _underlyingTokenIndex[_stablecoin] - 1
        ] = _minAmount;
        request.userData = abi.encode(
            0,
            _lpTokens,
            _underlyingTokenIndex[_stablecoin] - 1
        ); // EXACT_BPT_IN_FOR_ONE_TOKEN_OUT
        IBalancerVault(VAULT).exitPool(
            BALANCER_POOL_ID,
            address(this),
            payable(address(this)),
            request
        );

        received = IERC20(_stablecoin).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev Withdraw to USDT
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _removeLiquidityToUSDT(
        uint _lpTokens,
        uint _minAmount
    ) internal override returns (uint256 received) {
        return _removeLiquidityToStablecoin(USDT_TOKEN, _lpTokens, _minAmount);
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

        IBalancerVault.ExitPoolRequest memory request;
        request.assets = _underlyingTokens;
        request.minAmountsOut = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            request.minAmountsOut[i] = _minAmounts[i];
        }
        /// @dev use different ExitKind for ComposableStablePool
        request.userData = abi.encode(1, _lpTokens); // EXACT_BPT_IN_FOR_TOKENS_OUT
        IBalancerVault(VAULT).exitPool(
            BALANCER_POOL_ID,
            address(this),
            payable(address(this)),
            request
        );

        for (uint256 i = 0; i < length; ++i) {
            emergencyWithdrawnTokens[i] =
                IERC20(_underlyingTokens[i]).balanceOf(address(this)) -
                balanceBefore[i];
        }
    }
}
