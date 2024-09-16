//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.9;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import 'contracts/fees/INeuralFeeHandler.sol';
import 'contracts/token/Neural.sol';
import 'contracts/access/OracleManaged.sol';

/// @title Neural fee handler
contract NeuralFeeHandler is OracleManaged, ReentrancyGuard, INeuralFeeHandler {
    using SafeERC20 for IERC20;
    using SafeERC20 for Neural;

    uint public buyBackFee = 0;
    uint public treasuryFee = 2000;
    uint public stakingFee = 0;
    uint public threshold = 100000000;
    uint constant DENOMINATOR = 10000;

    // Uniswap V2 Router
    address public constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public neural;
    address public staking;
    address public treasury;

    event FeeProcessed(
        uint buyBackAmount,
        uint stakingAmount,
        uint treasuryAmount
    );
    event FeeUpdated(uint buyBackFee, uint treasuryFee, uint stakingFee);
    event ThresholdUpdated(uint threshold);
    event NeuralAddressAdded(address neural);
    event TreasuryAddressUpdated(address treasury);
    event StakingAddressUpdated(address staking);

    /// @param _oracle Oracle address
    /// @param _treasury Treasury address
    /// @param _staking Staking address
    constructor(address _oracle, address _staking, address _treasury) {
        require(
            _staking != address(0),
            'NeuralFeeHandler: _staking cannot be the zero address'
        );
        require(
            _treasury != address(0),
            'NeuralFeeHandler: _treasury cannot be the zero address'
        );
        _setOracle(_oracle);
        staking = _staking;
        treasury = _treasury;
    }

    /// @notice Set the Neural address (can only be set once)
    /// @param _neural Neural address
    function setNeural(address _neural) external onlyOwner {
        require(
            neural == address(0),
            'NeuralFeeHandler: Neural address has already been set'
        );
        require(
            _neural != address(0),
            'NeuralFeeHandler: _neural cannot be the zero address'
        );
        neural = _neural;
        emit NeuralAddressAdded(neural);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(
            _treasury != address(0),
            'NeuralFeeHandler: _treasury cannot be the zero address'
        );
        treasury = _treasury;
        emit TreasuryAddressUpdated(_treasury);
    }

    function setStaking(address _staking) external onlyOwner {
        require(
            _staking != address(0),
            'NeuralFeeHandler: _staking cannot be the zero address'
        );
        staking = _staking;
        emit StakingAddressUpdated(_staking);
    }

    /// @notice Process USDT fee
    /// @param _minNeuralAmount Minimum expected Neural to be received from Uniswap for burning, can be 0 if buy back fee is 0%
    function processFee(
        uint _minNeuralAmount
    ) external nonReentrant onlyOracle {
        require(
            getFee() > 0,
            'NeuralFeeHandler: Cannot process fee due to total fee percent being 0'
        );
        require(
            isBalanceAboveThreshold(),
            'NeuralFeeHandler: Fee is less than threshold'
        );
        require(
            _minNeuralAmount > 0 || buyBackFee == 0,
            'NeuralFeeHandler: _minNeuralAmount cannot be zero'
        );

        (
            uint buyBackAmount,
            uint stakingAmount,
            uint treasuryAmount
        ) = getFeeAmounts();

        if (buyBackAmount > 0) {
            _handleBuyBackFee(buyBackAmount, _minNeuralAmount);
        }
        if (stakingAmount > 0) {
            _handleStakingFee(stakingAmount);
        }
        if (treasuryAmount > 0) {
            _handleTreasuryFee(treasuryAmount);
        }

        emit FeeProcessed(buyBackAmount, stakingAmount, treasuryAmount);
    }

    /// @notice Check if the contract's USDT balance is greater than or equal to the processing fee threshold
    /// @return bool true if it is greater than or equal to the threshold, false if not
    function isBalanceAboveThreshold() public view returns (bool) {
        uint amount = IERC20(usdt).balanceOf(address(this));
        return amount >= threshold;
    }

    /// @notice Get the amount of USDT split into each type of fee
    /// @return buyBackAmount Amount of USDT used in the buyback
    /// @return stakingAmount Amount of USDT to be sent to the staking address
    /// @return treasuryAmount Amount of USDT to be sent to the treasury address
    function getFeeAmounts()
        public
        view
        returns (uint buyBackAmount, uint stakingAmount, uint treasuryAmount)
    {
        uint totalFee = getFee();
        if (totalFee > 0) {
            uint amount = IERC20(usdt).balanceOf(address(this));
            buyBackAmount = (amount * buyBackFee) / totalFee;
            stakingAmount = (amount * stakingFee) / totalFee;
            treasuryAmount = amount - stakingAmount - buyBackAmount;
        }
        return (buyBackAmount, stakingAmount, treasuryAmount);
    }

    /// @notice Calculate the fee charged on an amount
    /// @param _amount Amount
    /// @return uint Fee
    function calculateFee(uint _amount) external view returns (uint) {
        return (_amount * getFee()) / DENOMINATOR;
    }

    /// @notice Get the total fee
    /// @return uint Total fee
    function getFee() public view returns (uint) {
        return buyBackFee + stakingFee + treasuryFee;
    }

    /// @notice Set the Neural fee, max combined fee is 2000 (20%)
    /// @param _buyBackFee Fee for buying back Neural, 2 d.p.
    /// @param _stakingFee Fee for staking, 2 d.p.
    /// @param _treasuryFee Fee for treasury, 2 d.p.
    function setFee(
        uint _buyBackFee,
        uint _stakingFee,
        uint _treasuryFee
    ) external onlyOwner {
        require(
            _buyBackFee == 0 || neural != address(0),
            'NeuralFeeHandler: Neural address needs to be configured to set a buyback fee'
        );
        require(
            _buyBackFee + _stakingFee + _treasuryFee <= 2000,
            'NeuralFeeHandler: Fee must be less than 20%'
        );
        buyBackFee = _buyBackFee;
        stakingFee = _stakingFee;
        treasuryFee = _treasuryFee;
        emit FeeUpdated(_buyBackFee, _stakingFee, _treasuryFee);
    }

    /// @notice Set processing fee threshold
    /// @param _threshold Threshold for processing the fee
    function setThreshold(uint _threshold) external onlyOwner {
        threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    /// @param _amount Buy back amount in USDT
    /// @param _minNeuralAmount Minimum expected Neural received from swapping USDT
    function _handleBuyBackFee(uint _amount, uint _minNeuralAmount) internal {
        _swapUSDTToNeural(_amount, _minNeuralAmount);
        _burnNeural();
    }

    /// @param _amount Staking amount in USDT
    function _handleStakingFee(uint _amount) internal {
        IERC20(usdt).safeTransfer(staking, _amount);
    }

    /// @param _amount Treasury amount in USDT
    function _handleTreasuryFee(uint _amount) internal {
        IERC20(usdt).safeTransfer(treasury, _amount);
    }

    /// @param _amount USDT to swap to Neural
    /// @param _minNeuralAmount Minimum expected Neural received from swapping USDT
    function _swapUSDTToNeural(uint _amount, uint _minNeuralAmount) internal {
        IERC20(usdt).safeIncreaseAllowance(router, _amount);

        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = neural;
        IUniswapV2Router02(router).swapExactTokensForTokens(
            _amount,
            _minNeuralAmount,
            path,
            address(this),
            block.timestamp + 100
        );
    }

    /// @dev Burn Neural tokens
    function _burnNeural() internal {
        uint neuralBalance = Neural(payable(neural)).balanceOf(address(this));
        Neural(payable(neural)).burn(neuralBalance);
    }
}
