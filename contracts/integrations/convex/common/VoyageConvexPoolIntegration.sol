//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/interfaces/IUniswapV3Router.sol';
import 'contracts/fees/IVoyageFeeHandler.sol';
import 'contracts/integrations/common/VoyageLPIntegration.sol';
import 'contracts/integrations/convex/common/IConvexBooster.sol';
import 'contracts/integrations/convex/common/IConvexRewards.sol';
import 'contracts/integrations/curve/common/ICurve3CRVBasePool.sol';

/// @title Voyage Convex stablecoin pool integration
contract VoyageConvexPoolIntegration is VoyageLPIntegration {
    using SafeERC20 for IERC20;

    /// @dev Convex contracts
    address internal constant BOOSTER =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @dev LP configurations
    uint256 internal CONVEX_PID; // Convex Pool ID
    address internal CONVEX_LP_TOKEN; // Convex LP token address
    address internal CONVEX_REWARDS; // Rewards (Curve / Convex) distribution contract
    address[] internal _underlyingTokens;
    mapping(address => uint256) internal _underlyingTokenIndex; // starts from `1`

    uint256[3] public emergencyWithdrawnTokens;

    /// @dev Stablecoin for the reward
    address internal constant USDT_TOKEN =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @dev Convex reward tokens
    address internal constant CRV_TOKEN =
        0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX_TOKEN =
        0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @dev Swap configurations
    address internal constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant USDC_TOKEN =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    receive() external payable {}

    /// @param _pid Convex Pool ID
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        uint256 _pid,
        address _oracle,
        address _feeHandler
    ) VoyageLPIntegration(_oracle, _feeHandler) {
        CONVEX_PID = _pid;
        (CONVEX_LP_TOKEN, , , CONVEX_REWARDS, , ) = IConvexBooster(BOOSTER)
            .poolInfo(_pid);

        _queryUnderlyings();
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
        lpTokens = IERC20(CONVEX_LP_TOKEN).balanceOf(address(this));
        IERC20(CONVEX_LP_TOKEN).safeIncreaseAllowance(BOOSTER, lpTokens);
        IConvexBooster(BOOSTER).deposit(CONVEX_PID, lpTokens, true);
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
        IConvexRewards(CONVEX_REWARDS).withdrawAndUnwrap(_lpTokens, false);

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
        IConvexRewards(CONVEX_REWARDS).getReward(address(this), true);

        // CRV -> USDC
        _swapCRVToUSDC();

        // CVX -> USDC
        _swapCVXToUSDC();

        // USDC -> USDT
        rewards = _swapUSDCToUSDT(_minAmounts[0]);

        rewards += _swapExtraRewards(_minAmounts[1]);

        return rewards;
    }

    /// @dev Withdraw all LP in base tokens
    /// @param _lpTokens Amount of Convex LP tokens
    /// @param _minAmounts Minimum amounts for withdrawal (underlying tokens)
    function _farmEmergencyWithdrawal(
        uint _lpTokens,
        uint[10] memory _minAmounts
    ) internal override {
        // unstake and withdraw
        IConvexRewards(CONVEX_REWARDS).withdrawAndUnwrap(_lpTokens, false);

        // exit LP
        _exitPoolForEmergencyWithdraw(_lpTokens, _minAmounts);
    }

    /// @dev Transfer pro rata amount of stablecoins to user
    function _withdrawAfterShutdown() internal override {
        _mergeRewards();
        for (uint i; i < 3; i++) {
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
            'VoyageConvexPoolIntegration: Only USDT'
        );
        _mergeRewards();
        uint heldRewards = users[_msgSender()].heldRewards; // USDT
        require(
            heldRewards > _minAmount,
            'VoyageConvexPoolIntegration: Not enough rewards'
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
            'VoyageConvexPoolIntegration: Not enough fees'
        );
        totalUnhandledFee = 0;

        IERC20(USDT_TOKEN).safeTransfer(feeHandler, fee);
    }

    /// @dev swap CRV to USDC
    function _swapCRVToUSDC() internal {
        uint256 swapAmount = IERC20(CRV_TOKEN).balanceOf(address(this));
        IERC20(CRV_TOKEN).safeIncreaseAllowance(UNISWAP_V3_ROUTER, swapAmount);

        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = CRV_TOKEN;
        params.tokenOut = USDC_TOKEN;
        params.fee = 10000;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = swapAmount;
        params.amountOutMinimum = 1;
        params.sqrtPriceLimitX96 = 0;

        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    /// @dev swap CONVEX to USDC
    function _swapCVXToUSDC() internal {
        uint256 swapAmount = IERC20(CVX_TOKEN).balanceOf(address(this));
        IERC20(CVX_TOKEN).safeIncreaseAllowance(UNISWAP_V3_ROUTER, swapAmount);

        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = CVX_TOKEN;
        params.tokenOut = USDC_TOKEN;
        params.fee = 3000;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = swapAmount;
        params.amountOutMinimum = 1;
        params.sqrtPriceLimitX96 = 0;

        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    /// @dev swap USDC to USDT (reward)
    function _swapUSDCToUSDT(
        uint256 _minAmount
    ) internal returns (uint256 reward) {
        uint256 swapAmount = IERC20(USDC_TOKEN).balanceOf(address(this));
        IERC20(USDC_TOKEN).safeIncreaseAllowance(UNISWAP_V3_ROUTER, swapAmount);

        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = USDC_TOKEN;
        params.tokenOut = USDT_TOKEN;
        params.fee = 100;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = swapAmount;
        params.amountOutMinimum = _minAmount;
        params.sqrtPriceLimitX96 = 0;

        uint256 balanceBefore = IERC20(USDT_TOKEN).balanceOf(address(this));
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);
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
