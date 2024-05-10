//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/interfaces/IUniswapV3Router.sol';
import 'contracts/fees/INeuralFeeHandler.sol';
import 'contracts/integrations/common/NeuralLPIntegration.sol';
import 'contracts/integrations/aura/common/IAuraBooster.sol';
import 'contracts/integrations/aura/common/IAuraRewards.sol';
import 'contracts/integrations/aura/common/IBalancerPool.sol';
import 'contracts/integrations/aura/common/IBalancerVault.sol';

/// @title Neural Aura stablecoin pool integration
contract NeuralAuraPoolIntegration is NeuralLPIntegration {
    using SafeERC20 for IERC20;

    /// @dev Aura contracts
    address internal constant BOOSTER =
        0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;

    /// @dev Balancer contracts
    address internal constant VAULT =
        0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /// @dev LP configurations
    bytes32 internal BALANCER_POOL_ID; // Balancer Pool ID
    uint256 internal AURA_PID; // Aura Pool ID
    address internal AURA_LP_TOKEN; // Aura LP token address
    address internal AURA_REWARDS; // Rewards (Bal / Aura) distribution contract
    address[] internal _underlyingTokens;
    mapping(address => uint256) internal _underlyingTokenIndex; // starts from `1`

    uint256[3] public emergencyWithdrawnTokens;

    /// @dev Stablecoin for the reward
    address internal constant USDT_TOKEN =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @dev Aura reward tokens
    address internal constant BAL_TOKEN =
        0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant AURA_TOKEN =
        0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// @dev Swap configurations
    address internal constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant WETH_TOKEN =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    receive() external payable {}

    /// @param _pid Aura Pool ID
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        uint256 _pid,
        address _oracle,
        address _feeHandler
    ) NeuralLPIntegration(_oracle, _feeHandler) {
        AURA_PID = _pid;
        (AURA_LP_TOKEN, , , AURA_REWARDS, , ) = IAuraBooster(BOOSTER).poolInfo(
            _pid
        );
        BALANCER_POOL_ID = IBalancerPool(AURA_LP_TOKEN).getPoolId();
        (address[] memory tokens, , ) = IBalancerVault(VAULT).getPoolTokens(
            BALANCER_POOL_ID
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            _underlyingTokenIndex[tokens[i]] = i + 1;
            _underlyingTokens.push(tokens[i]);
        }
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

        // deposit and stake
        lpTokens = IERC20(AURA_LP_TOKEN).balanceOf(address(this));
        IERC20(AURA_LP_TOKEN).safeIncreaseAllowance(BOOSTER, lpTokens);
        IAuraBooster(BOOSTER).deposit(AURA_PID, lpTokens, true);
    }

    /// @dev Withdraw stablecoins
    /// @param _stablecoin chosen stablecoin to withdraw
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _farmWithdrawal(
        address _stablecoin,
        uint _lpTokens,
        uint _minAmount
    ) internal override returns (uint received) {
        // unstake and withdraw
        IAuraRewards(AURA_REWARDS).withdrawAndUnwrap(_lpTokens, false);

        uint256 balanceBefore = IERC20(_stablecoin).balanceOf(address(this));
        // LP -> stablecoin
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

    /// @dev Claim Curve rewards and convert them to USDT
    /// @param _minAmounts Minimum swap amounts for harvesting, index 0: BAL / AURA -> USDT, index 1: Extra rewards -> USDT
    /// @return rewards Amount of USDT rewards harvested
    function _farmHarvest(
        uint[10] memory _minAmounts
    ) internal override returns (uint rewards) {
        IAuraRewards(AURA_REWARDS).getReward(address(this), true);

        // BAL -> WETH
        _swapBALToWETH();

        // AURA -> WETH
        _swapAURAToWETH();

        // WETH -> USDT
        rewards = _swapWETHToUSDT(_minAmounts[0]);

        rewards += _swapExtraRewards(_minAmounts[1]);

        return rewards;
    }

    /// @dev Withdraw all LP in base tokens
    /// @param _lpTokens Amount of Aura LP tokens
    /// @param _minAmounts Minimum amounts for withdrawal (underlying tokens)
    function _farmEmergencyWithdrawal(
        uint _lpTokens,
        uint[10] memory _minAmounts
    ) internal override {
        // unstake and withdraw
        IAuraRewards(AURA_REWARDS).withdrawAndUnwrap(_lpTokens, false);

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
            'NeuralAuraPoolIntegration: Only USDT'
        );
        _mergeRewards();
        uint heldRewards = users[_msgSender()].heldRewards; // USDT
        require(
            heldRewards > _minAmount,
            'NeuralAuraPoolIntegration: Not enough rewards'
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
            'NeuralAuraPoolIntegration: Not enough fees'
        );
        totalUnhandledFee = 0;

        IERC20(USDT_TOKEN).safeTransfer(feeHandler, fee);
    }

    /// @dev swap BAL to WETH
    function _swapBALToWETH() internal {
        uint256 amount = IERC20(BAL_TOKEN).balanceOf(address(this));
        IERC20(BAL_TOKEN).safeIncreaseAllowance(VAULT, amount);

        IBalancerVault.SingleSwap memory singleSwap;
        singleSwap
            .poolId = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014; // 80BAL/20WETH
        singleSwap.kind = IBalancerVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = BAL_TOKEN;
        singleSwap.assetOut = WETH_TOKEN;
        singleSwap.amount = amount;
        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.recipient = payable(address(this));
        IBalancerVault(VAULT).swap(singleSwap, funds, 0, block.timestamp);
    }

    /// @dev swap AURA to WETH
    function _swapAURAToWETH() internal {
        uint256 amount = IERC20(AURA_TOKEN).balanceOf(address(this));
        IERC20(AURA_TOKEN).safeIncreaseAllowance(VAULT, amount);

        IBalancerVault.SingleSwap memory singleSwap;
        singleSwap
            .poolId = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274; // 50WETH/50AURA
        singleSwap.kind = IBalancerVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = AURA_TOKEN;
        singleSwap.assetOut = WETH_TOKEN;
        singleSwap.amount = amount;
        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.recipient = payable(address(this));
        IBalancerVault(VAULT).swap(singleSwap, funds, 0, block.timestamp);
    }

    /// @dev swap WETH to USDT (reward)
    function _swapWETHToUSDT(
        uint256 _minAmount
    ) internal returns (uint256 reward) {
        uint256 swapAmount = IERC20(WETH_TOKEN).balanceOf(address(this));
        IERC20(WETH_TOKEN).safeIncreaseAllowance(UNISWAP_V3_ROUTER, swapAmount);

        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = WETH_TOKEN;
        params.tokenOut = USDT_TOKEN;
        params.fee = 3000;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = swapAmount;
        params.amountOutMinimum = _minAmount;
        params.sqrtPriceLimitX96 = 0;

        uint256 balanceBefore = IERC20(USDT_TOKEN).balanceOf(address(this));
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);
        reward = IERC20(USDT_TOKEN).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev exit LP and prepare emergency withdrawn tokens
    function _exitPoolForEmergencyWithdraw(
        uint256 _lpTokens,
        uint256[10] memory _minAmounts
    ) internal {
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

    /// @dev swap extra rewards to USDT (reward)
    function _swapExtraRewards(
        uint256 _minAmount
    ) internal virtual returns (uint256) {}
}
