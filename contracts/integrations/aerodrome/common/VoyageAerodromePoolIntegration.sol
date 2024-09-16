//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/interfaces/IUniswapV3Router.sol';
import 'contracts/fees/IVoyageFeeHandler.sol';
import 'contracts/integrations/common/VoyageLPIntegration.sol';
import 'contracts/integrations/aerodrome/common/IVeloPool.sol';
import 'contracts/integrations/aerodrome/common/IVeloGauge.sol';
import 'contracts/integrations/aerodrome/common/IVeloRouter.sol';
import 'contracts/integrations/curve/common/ICurve3CRVBasePool.sol';

/// @title Voyage Aerodrome stablecoin pool integration
contract VoyageAerodromePoolIntegration is VoyageLPIntegration {
    using SafeERC20 for IERC20;

    /// @dev Aerodrome contracts
    address internal constant AERODROME_ROUTER =
        0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    /// @dev LP configurations
    address internal AERODROME_LP_TOKEN; // Aerodrome LP token address
    address internal AERODROME_GAUGE; // Rewards (Curve / Aerodrome) distribution contract
    address[] internal _underlyingTokens;
    mapping(address => uint256) internal _underlyingTokenIndex; // starts from `1`

    uint256[3] public emergencyWithdrawnTokens;

    /// @dev Stablecoin for the reward
    address internal constant USDT_TOKEN =
        0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    /// @dev Aerodrome reward tokens
    address internal constant AERO_TOKEN =
        0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    /// @dev Swap configurations
    address internal constant USDC_TOKEN =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _lpToken,
        address _gauge,
        address _oracle,
        address _feeHandler
    ) VoyageLPIntegration(_oracle, _feeHandler) {
        AERODROME_LP_TOKEN = _lpToken;
        AERODROME_GAUGE = _gauge;

        address token0 = IVeloPool(_lpToken).token0();
        _underlyingTokenIndex[token0] = 1;
        _underlyingTokens.push(token0);
        address token1 = IVeloPool(_lpToken).token1();
        _underlyingTokenIndex[token1] = 2;
        _underlyingTokens.push(token1);
    }

    /// @notice Check if an address is an accepted deposit token
    /// @param _token Token address
    /// @return bool true if it is a supported deposit token, false if not
    function isDepositToken(
        address _token
    ) public view override returns (bool) {
        return _underlyingTokenIndex[_token] > 0;
    }

    /// @notice Check if an address is an accepted withdrawal token
    /// @param _token Token address
    /// @return bool true if it is a supported withdrawal token, false if not
    function isWithdrawalToken(
        address _token
    ) public view override returns (bool) {
        return _underlyingTokenIndex[_token] > 0;
    }

    /// @notice Check if an address is an accepted reward token
    /// @param _token Token address
    /// @return bool true if it is a supported reward token, false if not
    function isRewardToken(address _token) public pure override returns (bool) {
        return _token == USDT_TOKEN;
    }

    /// @dev Deposit stablecoins
    /// @param _stablecoin stablecoin to deposit
    /// @param _amount amount to deposit
    /// @param _minLPAmount minimum amount of LP to receive
    /// @return lpTokens Amount of LP tokens received from depositing
    function _farmDeposit(
        address _stablecoin,
        uint _amount,
        uint _minLPAmount
    ) internal override returns (uint lpTokens) {
        // stablecoin -> LP
        _depositStablecoin(_stablecoin, _amount, _minLPAmount);

        // deposit and stake
        lpTokens = IERC20(AERODROME_LP_TOKEN).balanceOf(address(this));
        IERC20(AERODROME_LP_TOKEN).safeIncreaseAllowance(
            AERODROME_GAUGE,
            lpTokens
        );
        IVeloGauge(AERODROME_GAUGE).deposit(lpTokens);
    }

    /// @dev Withdraw stablecoins
    /// @param _stablecoin chosen stablecoin to withdraw
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _farmWithdrawal(
        address _stablecoin,
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal override returns (uint received) {
        // unstake and withdraw
        IVeloGauge(AERODROME_GAUGE).withdraw(_lpTokens);

        uint256 balanceBefore = IERC20(_stablecoin).balanceOf(address(this));
        // LP -> stablecoin
        _withdrawStablecoin(_stablecoin, _lpTokens, _minAmount);

        received = IERC20(_stablecoin).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev Claim Curve rewards and convert them to USDT
    /// @param _minAmounts Minimum swap amounts for harvesting, index 0: CRV / CVX -> USDT, index 1: Extra rewards -> USDT
    /// @return rewards Amount of USDT rewards harvested
    function _farmHarvest(
        uint[10] memory _minAmounts
    ) internal override returns (uint rewards) {
        IVeloGauge(AERODROME_GAUGE).getReward(address(this));

        // AERO -> USDC
        _swapAEROToUSDC();

        // USDC -> USDT
        rewards = _swapUSDCToUSDT(_minAmounts[0]);

        rewards += _swapExtraRewards(_minAmounts[1]);

        return rewards;
    }

    /// @dev Withdraw all LP in base tokens
    /// @param _lpTokens Amount of Aerodrome LP tokens
    /// @param _minAmounts Minimum amounts for withdrawal (underlying tokens)
    function _farmEmergencyWithdrawal(
        uint _lpTokens,
        uint[10] memory _minAmounts
    ) internal override {
        // unstake and withdraw
        IVeloGauge(AERODROME_GAUGE).withdraw(_lpTokens);

        // exit LP
        _exitPoolForEmergencyWithdraw(_lpTokens, _minAmounts);
    }

    /// @dev Transfer pro rata amount of stablecoins to user
    function _withdrawAfterShutdown() internal override {
        _mergeRewards();
        for (uint i; i < 2; i++) {
            uint amount = (emergencyWithdrawnTokens[i] *
                users[_msgSender()].lpBalance) / totalActiveDeposits;
            IERC20(_underlyingTokens[i]).safeTransfer(_msgSender(), amount);
        }
    }

    /// @param _stablecoin Stablecoin address
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return rewards Rewards claimed in _stablecoin
    function _claimRewards(
        address _stablecoin,
        uint _minAmount
    ) internal override returns (uint rewards) {
        require(
            isRewardToken(_stablecoin),
            'VoyageAerodromePoolIntegration: Only USDT'
        );
        _mergeRewards();
        uint heldRewards = users[_msgSender()].heldRewards; // USDT
        require(
            heldRewards > _minAmount,
            'VoyageAerodromePoolIntegration: Not enough rewards'
        );

        users[_msgSender()].heldRewards = 0;

        IERC20(_stablecoin).safeTransfer(_msgSender(), heldRewards);
        return rewards;
    }

    /// @dev transfer USDT to fee handler contract
    /// @param _minAmount minimum amount of USDT to receive
    function _handleFee(uint _minAmount) internal override {
        uint fee = totalUnhandledFee;
        require(
            fee >= _minAmount,
            'VoyageAerodromePoolIntegration: Not enough fees'
        );
        totalUnhandledFee = 0;

        IERC20(USDT_TOKEN).safeTransfer(feeHandler, fee);
    }

    /// @dev swap AERO to USDC
    function _swapAEROToUSDC() internal {
        uint256 swapAmount = IERC20(AERO_TOKEN).balanceOf(address(this));
        IERC20(AERO_TOKEN).safeIncreaseAllowance(AERODROME_ROUTER, swapAmount);

        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = AERO_TOKEN;
        routes[0].to = USDC_TOKEN;
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
    }

    /// @dev swap USDC to USDT (reward)
    function _swapUSDCToUSDT(
        uint256 _minAmount
    ) internal returns (uint256 reward) {
        uint256 swapAmount = IERC20(USDC_TOKEN).balanceOf(address(this));
        IERC20(USDC_TOKEN).safeIncreaseAllowance(AERODROME_ROUTER, swapAmount);

        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0].from = USDC_TOKEN;
        routes[0].to = USDT_TOKEN;
        routes[0].stable = true;
        routes[0].factory = IVeloPool(AERODROME_LP_TOKEN).factory();

        uint256 balanceBefore = IERC20(USDT_TOKEN).balanceOf(address(this));

        // Swap `tokenIn` into `tokenOut`.
        IVeloRouter(AERODROME_ROUTER).swapExactTokensForTokens(
            swapAmount,
            _minAmount,
            routes,
            address(this),
            block.timestamp
        );

        reward = IERC20(USDT_TOKEN).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev query underlying tokens of the LP
    function _queryUnderlyings() internal virtual {}

    /// @dev deposit stablecoin to Curve LP
    function _depositStablecoin(
        address _stablecoin,
        uint256 _amount,
        uint256 _minLPAmount
    ) internal virtual {}

    /// @dev withdraw stablecoin from Curve LP
    function _withdrawStablecoin(
        address _stablecoin,
        uint256 _lpTokens,
        uint256 _minAmount
    ) internal virtual {}

    /// @dev exit LP and prepare emergency withdrawn tokens
    function _exitPoolForEmergencyWithdraw(
        uint256 _lpTokens,
        uint256[10] memory _minAmounts
    ) internal virtual {}

    /// @dev swap extra rewards to USDT (reward)
    function _swapExtraRewards(
        uint256 _minAmount
    ) internal virtual returns (uint256) {}
}
