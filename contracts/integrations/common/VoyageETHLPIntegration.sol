//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import 'contracts/access/OracleManaged.sol';
import 'contracts/fees/IVoyageFeeHandler.sol';

/// @title Voyage LP integration
abstract contract VoyageETHLPIntegration is OracleManaged, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable feeHandler;
    address public immutable ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint public totalActiveDeposits;
    uint public totalUnhandledFee;
    uint public currentRewardFactor;
    // @dev this is used to allow for decimals in the currentRewardValue
    uint internal constant rewardFactorAccuracy = 1 ether;
    uint public depositThreshold = 50 ether;
    uint public feeHandlingThreshold = 50 ether;

    bool public isShutdown;
    bool public isDepositingEnabled;

    struct User {
        uint rewardFactor;
        uint heldRewards;
        uint lpBalance;
        bool hasEmergencyWithdrawn;
    }

    mapping(address => User) public users;

    event Deposit(address user, uint amount, uint lpTokens);
    event Withdraw(address user, uint lpTokens, uint received);
    event ClaimRewards(address user, address stablecoin, uint rewards);
    event WithdrawAfterShutdown(address user);
    event DepositingEnabled();
    event DepositingDisabled();
    event FeeHandlingThresholdUpdated(uint feeHandlingThreshold);
    event EmergencyShutdown();
    event Harvest(uint total, uint rewards, uint fee);
    event RewardDistribution(uint rewards, uint currentActiveDeposits);
    event DepositThresholdUpdated(uint threshold);

    /// @param _token Token address
    modifier onlyDepositTokens(address _token) {
        require(
            isDepositToken(_token),
            'VoyageLPIntegration: Token is not a supported deposit token'
        );
        _;
    }

    /// @param _token Token address
    modifier onlyWithdrawalTokens(address _token) {
        require(
            isWithdrawalToken(_token),
            'VoyageLPIntegration: Token is not a supported withdrawal token'
        );
        _;
    }

    /// @param _token Token address
    modifier onlyRewardTokens(address _token) {
        require(
            isRewardToken(_token),
            'VoyageLPIntegration: Token is not a supported reward token'
        );
        _;
    }

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(address _oracle, address _feeHandler) {
        require(
            _feeHandler != address(0),
            'VoyageLPIntegration: _feeHandler cannot be the zero address'
        );
        _setOracle(_oracle);
        feeHandler = _feeHandler;
    }

    /// @notice Deposit ETH
    /// @param _minLPAmount Minimum amount of LP to receive
    function deposit(uint _minLPAmount) external payable nonReentrant {
        require(
            !isShutdown,
            'VoyageLPIntegration: Integration shutdown, depositing is no longer available'
        );
        require(
            isDepositingEnabled,
            'VoyageLPIntegration: Depositing is not allowed at this time'
        );
        uint depositAmount = msg.value;
        require(
            depositAmount >= depositThreshold && depositAmount > 0,
            'VoyageLPIntegration: Deposit threshold not met'
        );

        uint lpTokens = _deposit(depositAmount, _minLPAmount);
        emit Deposit(_msgSender(), depositAmount, lpTokens);
    }

    /// @notice Withdraw ETH
    /// @param _lpTokens Amount of LP tokens to remove from pool in ETH
    /// @param _minAmount Minimum amount of desired ETH
    function withdraw(uint _lpTokens, uint _minAmount) external nonReentrant {
        require(
            !isShutdown,
            'VoyageLPIntegration: Cannot withdraw using this function, use withdrawAfterShutdown instead'
        );
        require(_lpTokens > 0, 'VoyageLPIntegration: _lpTokens is invalid');
        uint received = _withdraw(_lpTokens, _minAmount);
        emit Withdraw(_msgSender(), _lpTokens, received);
    }

    /// @notice Claim rewards from the contract
    /// @param _stablecoin Desired stablecoin to receive rewards in
    /// @param _minAmount Minimum amount of desired stablecoin
    function claimRewards(
        address _stablecoin,
        uint _minAmount
    ) external nonReentrant onlyRewardTokens(_stablecoin) {
        uint rewards = _claimRewards(_stablecoin, _minAmount);
        emit ClaimRewards(_msgSender(), _stablecoin, rewards);
    }

    /// @notice Withdraw stablecoins after the contract has been shutdown
    function withdrawAfterShutdown() external nonReentrant {
        require(
            isShutdown,
            'VoyageLPIntegration: Cannot withdraw using this function, use withdraw instead'
        );
        require(
            !users[_msgSender()].hasEmergencyWithdrawn &&
                users[_msgSender()].lpBalance > 0,
            'VoyageLPIntegration: Nothing to withdraw'
        );
        users[_msgSender()].hasEmergencyWithdrawn = true;
        _withdrawAfterShutdown();
        emit WithdrawAfterShutdown(_msgSender());
    }

    /// @notice Harvest farm rewards (if there are any) and store them in the contract
    /// @param _minAmounts Minimum amounts for harvesting, data is specific to integration
    function harvest(
        uint[10] memory _minAmounts
    ) external onlyOwnerOrOracle nonReentrant {
        _harvest(_minAmounts);
    }

    /// @notice Handle the collected fee and transfer to VoyageFeeHandler
    /// @param _minAmount minimum amount of stablecoin to receive
    function handleFee(
        uint _minAmount
    ) external onlyOwnerOrOracle nonReentrant {
        require(
            totalUnhandledFee > 0,
            'VoyageLPIntegration: No fees to handle'
        );
        require(
            isShutdown || totalUnhandledFee >= feeHandlingThreshold,
            'VoyageLPIntegration: Collected fees are below threshold'
        );
        _handleFee(_minAmount);
    }

    /// @notice Remove liquidity from farm and leave tokens in the contract for user's to claim pro rata
    /// @param _minAmounts Minimum amounts for removing liquidity, data is specific to integration
    function emergencyShutdown(
        uint[10] memory _minAmounts
    ) external onlyOwnerOrOracle {
        require(
            !isShutdown,
            'VoyageLPIntegration: Integration is already shutdown'
        );
        isShutdown = true;
        _emergencyShutdown(_minAmounts);
        emit EmergencyShutdown();
    }

    /// @notice Enable depositing
    function enableDepositing() external onlyOwner {
        require(
            !isShutdown,
            'VoyageLPIntegration: Enabling deposits is not allowed due to the integration being shutdown'
        );
        isDepositingEnabled = true;
        emit DepositingEnabled();
    }

    /// @notice Disable depositing
    function disableDepositing() external onlyOwner {
        require(
            !isShutdown,
            'VoyageLPIntegration: Deposits are already disabled due to the integration being shutdown'
        );
        isDepositingEnabled = false;
        emit DepositingDisabled();
    }

    /// @notice Set the deposit threshold
    /// @param _threshold Deposit threshold
    function setDepositThreshold(uint _threshold) external onlyOwner {
        depositThreshold = _threshold;
        emit DepositThresholdUpdated(_threshold);
    }

    /// @notice Set the threshold the unhandled fee needs to reach before it can be handled
    /// @param _threshold Fee handling threshold
    function setFeeHandlingThreshold(uint _threshold) external onlyOwner {
        feeHandlingThreshold = _threshold;
        emit FeeHandlingThresholdUpdated(feeHandlingThreshold);
    }

    /// @notice Get the LP balance acquired from depositing for a user
    /// @param _user User address
    /// @return uint User's LP balance
    function getLPBalance(address _user) external view virtual returns (uint) {
        return users[_user].lpBalance;
    }

    /// @notice Get the current rewards for a user
    /// @param _user User address
    /// @return uint Current rewards for _user
    function getReward(address _user) external view virtual returns (uint) {
        return _getHeldRewards(_user) + _getCalculatedRewards(_user);
    }

    /// @notice Check if an address is an accepted deposit token
    /// @param _token Token address
    /// @return bool true if it is a supported deposit token, false if not
    function isDepositToken(address _token) public view virtual returns (bool);

    /// @notice Check if an address is an accepted withdrawal token
    /// @param _token Token address
    /// @return bool true if it is a supported withdrawal token, false if not
    function isWithdrawalToken(
        address _token
    ) public view virtual returns (bool);

    /// @notice Check if an address is an accepted reward token
    /// @param _token Token address
    /// @return bool true if it is a supported reward token, false if not
    function isRewardToken(address _token) public view virtual returns (bool);

    /// @param _user User address
    /// @return uint Held rewards
    function _getHeldRewards(
        address _user
    ) internal view virtual returns (uint) {
        return users[_user].heldRewards;
    }

    /// @param _user User address
    /// @return uint Calculated rewards
    function _getCalculatedRewards(
        address _user
    ) internal view virtual returns (uint) {
        uint balance = users[_user].lpBalance;
        return
            (balance * (currentRewardFactor - users[_user].rewardFactor)) /
            rewardFactorAccuracy;
    }

    /// @dev Merge held rewards with calculated rewards
    function _mergeRewards() internal virtual {
        _holdCalculatedRewards();
        users[_msgSender()].rewardFactor = currentRewardFactor;
    }

    /// @dev Convert calculated rewards into held rewards
    /// @dev Used when the user carries out an action that would cause their calculated rewards to change unexpectedly
    function _holdCalculatedRewards() internal virtual {
        uint calculatedReward = _getCalculatedRewards(_msgSender());
        if (calculatedReward > 0) {
            users[_msgSender()].heldRewards += calculatedReward;
        }
    }

    /// @param _amount Amount of _stablecoin to deposit
    /// @param _minLPAmount Minimum amount of LP to receive
    /// @return lpTokens Amount of LP tokens received from depositing
    function _deposit(
        uint _amount,
        uint _minLPAmount
    ) internal virtual returns (uint lpTokens) {
        _mergeRewards();

        lpTokens = _farmDeposit(_amount, _minLPAmount);
        users[_msgSender()].lpBalance += lpTokens;
        totalActiveDeposits += lpTokens;
        return lpTokens;
    }

    /// @param _lpTokens Amount of LP tokens to remove from pool in the _stablecoin
    /// @param _minAmount Minimum amount of _stablecoin to receive
    /// @return received Amount of _stablecoin received from withdrawing _lpTokens
    function _withdraw(
        uint _lpTokens,
        uint _minAmount
    ) internal virtual returns (uint received) {
        require(
            _lpTokens <= users[_msgSender()].lpBalance,
            'VoyageLPIntegration: Amount exceeds your LP balance'
        );
        _mergeRewards();

        users[_msgSender()].lpBalance -= _lpTokens;
        totalActiveDeposits -= _lpTokens;

        received = _farmWithdrawal(_lpTokens, _minAmount);

        payable(_msgSender()).transfer(received);
        return received;
    }

    /// @param _minAmounts Minimum amounts for harvesting, data is specific to integration
    function _harvest(uint[10] memory _minAmounts) internal virtual {
        uint total = _farmHarvest(_minAmounts);
        uint fee = IVoyageFeeHandler(feeHandler).calculateFee(total);
        uint rewards = total - fee;
        _distribute(rewards);
        totalUnhandledFee += fee;
        emit Harvest(total, rewards, fee);
    }

    /// @param _rewards Amount of rewards to distribute
    function _distribute(uint _rewards) internal virtual {
        require(
            totalActiveDeposits > 0,
            'VoyageLPIntegration: No active deposits'
        );
        currentRewardFactor +=
            (rewardFactorAccuracy * _rewards) /
            totalActiveDeposits;
        emit RewardDistribution(_rewards, totalActiveDeposits);
    }

    /// @dev Perform an emergency withdrawal
    function _emergencyShutdown(uint[10] memory _minAmounts) internal virtual {
        _farmEmergencyWithdrawal(totalActiveDeposits, _minAmounts);
    }

    /// @dev Convert amount of stablecoins to 18 decimals
    /// @param _stablecoin Stablecoin address
    /// @param _amount Amount of _stablecoin
    /// @return uint Normalized amount
    function _normalize(
        address _stablecoin,
        uint _amount
    ) internal view returns (uint) {
        uint8 decimals = IERC20Metadata(_stablecoin).decimals();
        if (decimals > 18) {
            return _amount / 10 ** (decimals - 18);
        } else if (decimals < 18) {
            return _amount * 10 ** (18 - decimals);
        }
        return _amount;
    }

    function _farmDeposit(
        uint _amount,
        uint _minLPAmount
    ) internal virtual returns (uint lpTokens);

    function _farmWithdrawal(
        uint _lpTokens,
        uint _minAmount
    ) internal virtual returns (uint received);

    function _farmEmergencyWithdrawal(
        uint _lpTokens,
        uint[10] memory _minAmounts
    ) internal virtual;

    function _farmHarvest(
        uint[10] memory _minAmounts
    ) internal virtual returns (uint rewards);

    function _withdrawAfterShutdown() internal virtual;

    function _claimRewards(
        address _stablecoin,
        uint _minAmount
    ) internal virtual returns (uint rewards);

    function _handleFee(uint _minAmount) internal virtual;

    receive() external payable {}
}
