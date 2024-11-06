//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.9;

import 'contracts/staking/common/VoyageStaking.sol';
import 'contracts/token/OperatingSystem.sol';

/// @title Voyage staking
contract VoyageTokenStaking is VoyageStaking {
    OperatingSystem public immutable receipt;

    /// @param _voyage Voyage token
    /// @param _rewardToken Reward token
    /// @param _operatingSystem Voyage governance token
    /// @param _totalRewards Total rewards allocated for the contract
    /// @param _minimumDeposit Minimum deposit amount
    /// @param _apr1Month APR for 1 month to 1 d.p. e.g. 80 = 8%
    /// @param _apr3Month APR for 3 month to 1 d.p. e.g. 120 = 12%
    /// @param _apr6Month APR for 6 month to 1 d.p. e.g. 200 = 20%
    /// @param _apr12Month APR for 12 month to 1 d.p. e.g. 365 = 36.5%
    constructor(
        address _voyage,
        address _rewardToken,
        address _operatingSystem,
        uint _totalRewards,
        uint _minimumDeposit,
        uint _apr1Month,
        uint _apr3Month,
        uint _apr6Month,
        uint _apr12Month
    )
        VoyageStaking(
            _voyage,
            _rewardToken,
            _totalRewards,
            _minimumDeposit,
            _apr1Month,
            _apr3Month,
            _apr6Month,
            _apr12Month
        )
    {
        require(
            _operatingSystem != address(0),
            'VoyageTokenStaking: _operatingSystem cannot be the zero address'
        );
        receipt = OperatingSystem(_operatingSystem);
    }

    /// @dev Calculate the rewards earned at the end of the lockup period for a given amount of LP
    function _calculateReward(
        uint _amount,
        uint _lockUpPeriodType
    ) internal view override returns (uint reward) {
        uint period = getLockUpPeriod(_lockUpPeriodType);
        uint apr = getAPR(_lockUpPeriodType);
        return (_amount * apr * period) / (365 days * APR_DENOMINATOR);
    }

    function _giveReceipt(address _user, uint _amount) internal override {
        receipt.mint(_user, _amount);
    }

    function _takeReceipt(address _user, uint _amount) internal override {
        receipt.burnFrom(_user, _amount);
    }
}
