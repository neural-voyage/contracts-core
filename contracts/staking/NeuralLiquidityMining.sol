//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.9;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import 'contracts/staking/common/NeuralStaking.sol';
import 'contracts/access/OracleManaged.sol';

/// @title Neural liquidity mining
contract NeuralLiquidityMining is NeuralStaking, OracleManaged {
    uint public constant MAXIMUM_LIFETIME_PERIOD = 30 days;

    uint public lpPrice;
    uint public lpPriceExpiresAt;

    event LPValueUpdated(uint lpPrice, uint lpPriceExpiresAt);

    /// @param _oracle Oracle address
    /// @param _lpToken LP token address
    /// @param _neural Neural token
    /// @param _totalRewards Total rewards allocated for the contract
    /// @param _minimumDeposit Minimum deposit amount
    /// @param _apr1Month APR for 1 month to 1 d.p. e.g. 80 = 8%
    /// @param _apr3Month APR for 3 month to 1 d.p. e.g. 120 = 12%
    /// @param _apr6Month APR for 6 month to 1 d.p. e.g. 200 = 20%
    /// @param _apr12Month APR for 12 month to 1 d.p. e.g. 365 = 36.5%
    constructor(
        address _oracle,
        address _lpToken,
        address _neural,
        uint _totalRewards,
        uint _minimumDeposit,
        uint _apr1Month,
        uint _apr3Month,
        uint _apr6Month,
        uint _apr12Month
    )
        NeuralStaking(
            _lpToken,
            _neural,
            _totalRewards,
            _minimumDeposit,
            _apr1Month,
            _apr3Month,
            _apr6Month,
            _apr12Month
        )
    {
        _setOracle(_oracle);
        IUniswapV2Pair lpToken = IUniswapV2Pair(_lpToken);
        require(
            lpToken.token0() == _neural || lpToken.token1() == _neural,
            'NeuralLiquidityMining: _lpToken pair does not contain _neural'
        );
    }

    /// @notice Get value of LP in Neural based on oracle/owner defined price
    /// @param _amount Amount of LP
    /// @return uint Equivalent value of _amount in Neural
    function getLPValue(uint _amount) external view returns (uint) {
        if (_isLPPriceValid()) {
            return _getLPValue(_amount);
        }
        return 0;
    }

    /// @notice Set LP price and lifetime for this price
    /// @param _lpPrice Amount of Neural for 1 LP token
    /// @param _lifeTimePeriod Lifetime period for _lpPrice, in seconds. Cannot be greater than the maximum lifetime period
    function setLPValue(
        uint _lpPrice,
        uint _lifeTimePeriod
    ) external onlyOwnerOrOracle {
        require(_lpPrice > 0, 'NeuralLiquidityMining: _lpPrice cannot be zero');
        require(
            _lifeTimePeriod <= MAXIMUM_LIFETIME_PERIOD,
            'NeuralLiquidityMining: _lifeTimePeriod is greater than the maximum lifetime period'
        );
        lpPrice = _lpPrice;
        lpPriceExpiresAt = block.timestamp + _lifeTimePeriod;
        emit LPValueUpdated(lpPrice, lpPriceExpiresAt);
    }

    /// @dev Calculate the rewards earned at the end of the lockup period for a given amount of LP, reverts if LP price has expired
    function _calculateReward(
        uint _amount,
        uint _lockUpPeriodType
    ) internal view override returns (uint reward) {
        /// @dev convert LP amount to Neural
        require(
            _isLPPriceValid(),
            'NeuralLiquidityMining: LP price has expired'
        );
        uint neuralAmount = _getLPValue(_amount);
        uint period = getLockUpPeriod(_lockUpPeriodType);
        uint apr = getAPR(_lockUpPeriodType);
        return (neuralAmount * apr * period) / (365 days * APR_DENOMINATOR);
    }

    /// @dev get LP amount in Neural
    function _getLPValue(uint _amount) internal view returns (uint) {
        return (_amount * lpPrice) / 1 ether;
    }

    /// @dev LP price is valid if the current time is less than or equal to the expiration date
    function _isLPPriceValid() internal view returns (bool) {
        return block.timestamp <= lpPriceExpiresAt;
    }

    /// @dev no receipt token to give
    function _giveReceipt(address, uint) internal override {}

    /// @dev no receipt token to take
    function _takeReceipt(address, uint) internal override {}
}
