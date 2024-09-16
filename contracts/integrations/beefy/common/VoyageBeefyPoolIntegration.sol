//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/interfaces/IUniswapV3Router.sol';
import 'contracts/fees/IVoyageFeeHandler.sol';
import 'contracts/integrations/common/VoyageLPIntegration.sol';
import 'contracts/integrations/beefy/common/IBeefyVaultV7.sol';

/// @title Voyage Beefy stablecoin pool integration
contract VoyageBeefyPoolIntegration is VoyageLPIntegration {
    using SafeERC20 for IERC20;

    /// @dev Vault configurations
    address internal BEEFY_WANT;
    address internal BEEFY_VAULT;
    address[] internal _underlyingTokens;
    mapping(address => uint256) internal _underlyingTokenIndex; // starts from `1`
    uint256[3] public emergencyWithdrawnTokens;

    /// @dev Stablecoin for the reward
    address internal constant USDT_TOKEN =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;

    receive() external payable {}

    /// @param _vault beefy vault address
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _vault,
        address _oracle,
        address _feeHandler
    ) VoyageLPIntegration(_oracle, _feeHandler) {
        BEEFY_VAULT = _vault;
        BEEFY_WANT = IBeefyVaultV7(_vault).want();

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
    function isRewardToken(address _token) public view override returns (bool) {
        return _underlyingTokenIndex[_token] > 0;
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
        lpTokens = _addLiquidityWithStablecoin(
            _stablecoin,
            _amount,
            _minLPAmount
        );

        // deposit and stake
        IERC20(BEEFY_WANT).safeIncreaseAllowance(BEEFY_VAULT, lpTokens);
        IBeefyVaultV7(BEEFY_VAULT).deposit(lpTokens);
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
        _lpTokens = _withdrawFromVault(_lpTokens);

        received = _removeLiquidityToStablecoin(
            _stablecoin,
            _lpTokens,
            _minAmount
        );
    }

    /// @dev Claim Curve rewards and convert them to USDT
    /// @param _minAmounts Minimum swap amounts for harvesting, index 0: rewards as LP
    /// @return rewards Amount of USDT rewards harvested
    function _farmHarvest(
        uint[10] memory _minAmounts
    ) internal override returns (uint rewards) {
        uint256 totalShares = IERC20(BEEFY_VAULT).balanceOf(address(this));
        uint256 totalAssets = (totalShares *
            IBeefyVaultV7(BEEFY_VAULT).getPricePerFullShare()) / 1e18;

        if (totalAssets > totalActiveDeposits) {
            rewards = totalAssets - totalActiveDeposits;
        }

        rewards = _withdrawFromVault(rewards);

        require(
            rewards < _minAmounts[0],
            'VoyageBeefyPoolIntegration: Not enough rewards'
        );
    }

    /// @dev Withdraw all LP in base tokens
    /// @param _lpTokens Amount of Aura LP tokens
    /// @param _minAmounts Minimum amounts for withdrawal (underlying tokens)
    function _farmEmergencyWithdrawal(
        uint _lpTokens,
        uint[10] memory _minAmounts
    ) internal override {
        // unstake and withdraw
        _lpTokens = _withdrawFromVault(_lpTokens);

        // exit LP
        _exitPoolForEmergencyWithdraw(_lpTokens, _minAmounts);
    }

    /// @dev Transfer pro rata amount of stablecoins to user
    function _withdrawAfterShutdown() internal override {
        _mergeRewards();
        for (uint i; i < _underlyingTokens.length; ++i) {
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
            'VoyageBeefyPoolIntegration: Not reward token'
        );
        _mergeRewards();
        uint heldRewards = users[_msgSender()].heldRewards; // USDT
        require(
            heldRewards > _minAmount,
            'VoyageBeefyPoolIntegration: Not enough rewards'
        );

        users[_msgSender()].heldRewards = 0;

        rewards = _removeLiquidityToStablecoin(
            _stablecoin,
            heldRewards,
            _minAmount
        );

        IERC20(_stablecoin).safeTransfer(_msgSender(), heldRewards);
        return rewards;
    }

    /// @dev transfer USDT to fee handler contract
    /// @param _minAmount minimum amount of USDT to receive
    function _handleFee(uint _minAmount) internal override {
        uint fee = totalUnhandledFee;
        require(
            fee >= _minAmount,
            'VoyageBeefyPoolIntegration: Not enough fees'
        );
        totalUnhandledFee = 0;

        uint256 usdtFee = _removeLiquidityToUSDT(fee, _minAmount);

        IERC20(USDT_TOKEN).safeTransfer(feeHandler, usdtFee);
    }

    /// @dev withdraw LP from the vault contract
    function _withdrawFromVault(
        uint256 _lpTokens
    ) internal returns (uint256 actual) {
        uint256 balanceBefore = IERC20(BEEFY_WANT).balanceOf(address(this));
        uint256 share = (_lpTokens * 1e18) /
            IBeefyVaultV7(BEEFY_VAULT).getPricePerFullShare();
        IBeefyVaultV7(BEEFY_VAULT).withdraw(share);
        actual = IERC20(BEEFY_WANT).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev query underlying tokens of the LP
    function _queryUnderlyings() internal virtual {}

    /// @dev Deposit stablecoins
    /// @param _stablecoin stablecoin to deposit
    /// @param _amount amount to deposit
    /// @param _minLPAmount minimum amount of LP to receive
    /// @return lpTokens Amount of LP tokens received from depositing
    function _addLiquidityWithStablecoin(
        address _stablecoin,
        uint _amount,
        uint _minLPAmount
    ) internal virtual returns (uint256 lpTokens) {}

    /// @dev Withdraw stablecoins
    /// @param _stablecoin chosen stablecoin to withdraw
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _removeLiquidityToStablecoin(
        address _stablecoin,
        uint _lpTokens,
        uint _minAmount
    ) internal virtual returns (uint256 received) {}

    /// @dev Withdraw to USDT
    /// @param _lpTokens LP amount to remove
    /// @param _minAmount minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpToken
    function _removeLiquidityToUSDT(
        uint _lpTokens,
        uint _minAmount
    ) internal virtual returns (uint256 received) {}

    /// @dev exit LP and prepare emergency withdrawn tokens
    function _exitPoolForEmergencyWithdraw(
        uint256 _lpTokens,
        uint256[10] memory _minAmounts
    ) internal virtual {}
}
