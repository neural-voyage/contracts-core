//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IUniswapV2Pair} from '../interfaces/IUniswapV2Pair.sol';
import {IUniswapV2Factory} from '../interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Router02} from '../interfaces/IUniswapV2Router02.sol';
import {Babylonian} from '../libraries/Babylonian.sol';

/// @title Voyage Yield Network Native Token
contract Voyage is Ownable, ERC20Burnable, ERC20Pausable {
    using SafeERC20 for IERC20;

    /// @dev initial supply
    uint256 private constant INITIAL_SUPPLY = 100000000 ether; // 100 M

    /// @notice percent multiplier (100%)
    uint256 public constant MULTIPLIER = 10000;

    /// @notice Uniswap Router
    IUniswapV2Router02 public constant ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /// @notice tax info
    struct TaxInfo {
        uint256 liquidityFee;
        uint256 marketingFee;
    }
    TaxInfo public taxInfo;
    uint256 public uniswapFee;

    /// @notice liquidity wallet
    address public liquidityFeeReceiver;

    /// @notice marketing wallet
    address public marketingFeeReceiver;

    /// @notice max holding per wallet
    uint256 public maxHoldingPerWallet = 50; // 0.5%

    /// @notice whether a wallet excludes fees
    mapping(address => bool) public isExcludedFromFee;

    /// @notice whether a wallet excludes max wallet check
    mapping(address => bool) public isExcludedFromMaxHoldingCheck;

    /// @notice whether a wallet is blacklisted
    mapping(address => bool) public isBlacklisted;

    /// @notice pending tax
    uint256 public pendingBuyTax;
    uint256 public pendingSellTax;

    /// @notice swap enabled
    bool public swapEnabled = true;

    /// @notice swap threshold
    uint256 public swapThreshold = INITIAL_SUPPLY / 20000; // 0.005%

    /// @dev in swap
    bool private inSwap;

    /* ======== EVENTS ======== */

    event LiquidityFeeReceiver(address receiver);
    event MarketingFeeReceiver(address receiver);
    event TaxFee(uint256 liquidityFee, uint256 marketingFee);
    event UniswapFee(uint256 uniswapFee);
    event ExcludeFromFee(address account);
    event IncludeFromFee(address account);

    error INVALID_ADDRESS();
    error INVALID_FEE();
    error PAUSED();
    error MAX_BALANCE();
    error BLACKLISTED();
    error FAIL_TO_SEND_ETH();

    constructor() Ownable() ERC20('Voyage', 'VOY') {
        taxInfo.liquidityFee = 300; // 3%
        taxInfo.marketingFee = 300; // 3%
        uniswapFee = 3; // 0.3% (1000 = 100%)

        isExcludedFromFee[_msgSender()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromMaxHoldingCheck[_msgSender()] = true;
        isExcludedFromMaxHoldingCheck[address(this)] = true;

        _mint(_msgSender(), INITIAL_SUPPLY);
        _approve(address(this), address(ROUTER), type(uint256).max);
    }

    receive() external payable {}

    /* ======== MODIFIERS ======== */

    modifier swapping() {
        inSwap = true;

        _;

        inSwap = false;
    }

    /* ======== POLICY FUNCTIONS ======== */

    function setLiquidityFeeReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert INVALID_ADDRESS();

        liquidityFeeReceiver = receiver;

        emit LiquidityFeeReceiver(receiver);
    }

    function setMarketingFeeReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert INVALID_ADDRESS();

        marketingFeeReceiver = receiver;

        emit MarketingFeeReceiver(receiver);
    }

    function setTaxFee(
        uint256 liquidityFee,
        uint256 marketingFee
    ) external onlyOwner {
        uint256 totalFee = liquidityFee + marketingFee;
        if (totalFee == 0 || totalFee >= MULTIPLIER) revert INVALID_FEE();

        taxInfo.liquidityFee = liquidityFee;
        taxInfo.marketingFee = marketingFee;

        emit TaxFee(liquidityFee, marketingFee);
    }

    function setUniswapFee(uint256 fee) external onlyOwner {
        uniswapFee = fee;

        emit UniswapFee(fee);
    }

    function setSwapTaxSettings(
        bool enabled,
        uint256 threshold
    ) external onlyOwner {
        swapEnabled = enabled;
        swapThreshold = threshold;
    }

    function excludeFromFee(address account) external onlyOwner {
        isExcludedFromFee[account] = true;

        emit ExcludeFromFee(account);
    }

    function includeFromFee(address account) external onlyOwner {
        isExcludedFromFee[account] = false;

        emit IncludeFromFee(account);
    }

    function excludeFromMaxHoldingCheck(address account) external onlyOwner {
        isExcludedFromMaxHoldingCheck[account] = true;
    }

    function includeFromMaxHoldingCheck(address account) external onlyOwner {
        isExcludedFromMaxHoldingCheck[account] = false;
    }

    function blacklist(
        address[] memory accounts,
        bool blacklisted
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isBlacklisted[accounts[i]] = blacklisted;
        }
    }

    function setMaxHoldingPerWallet(
        uint256 _maxHoldingPerWallet
    ) external onlyOwner {
        maxHoldingPerWallet = _maxHoldingPerWallet;
    }

    function recoverERC20(IERC20 token) external onlyOwner {
        if (address(token) == address(this)) {
            token.safeTransfer(
                _msgSender(),
                token.balanceOf(address(this)) - pendingBuyTax - pendingSellTax
            );
        } else {
            token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

    function recoverETH() external onlyOwner {
        uint256 amount = address(this).balance;

        if (amount > 0) {
            payable(_msgSender()).call{value: amount}('');
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ======== PUBLIC FUNCTIONS ======== */

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transferWithTax(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transferWithTax(from, to, amount);
        return true;
    }

    /* ======== INTERNAL FUNCTIONS ======== */

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Pausable) {
        if (isBlacklisted[from] || isBlacklisted[to]) revert BLACKLISTED();
        if (from != address(0) && paused()) revert PAUSED();

        if (
            !isExcludedFromMaxHoldingCheck[to] &&
            balanceOf(to) + amount >
            (totalSupply() * maxHoldingPerWallet) / MULTIPLIER
        ) {
            revert MAX_BALANCE();
        }
    }

    function _getPoolToken(
        address pool,
        string memory signature,
        function() external view returns (address) getter
    ) internal returns (address) {
        (bool success, ) = pool.call(abi.encodeWithSignature(signature));

        if (success) {
            uint32 size;
            assembly {
                size := extcodesize(pool)
            }
            if (size > 0) {
                return getter();
            }
        }

        return address(0);
    }

    function _shouldTakeBuyTax(
        address from,
        address to
    ) internal returns (bool) {
        if (isExcludedFromFee[from] || isExcludedFromFee[to]) return false;

        address token0 = _getPoolToken(
            from,
            'token0()',
            IUniswapV2Pair(from).token0
        );
        address token1 = _getPoolToken(
            from,
            'token1()',
            IUniswapV2Pair(from).token1
        );

        return token0 == address(this) || token1 == address(this);
    }

    function _shouldTakeSellTax(
        address from,
        address to
    ) internal returns (bool) {
        if (isExcludedFromFee[from] || isExcludedFromFee[to]) return false;

        address token0 = _getPoolToken(
            to,
            'token0()',
            IUniswapV2Pair(to).token0
        );
        address token1 = _getPoolToken(
            to,
            'token1()',
            IUniswapV2Pair(to).token1
        );

        return token0 == address(this) || token1 == address(this);
    }

    // use sell tax for liquidity fee
    function _swapSellTax() internal swapping {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = ROUTER.WETH();

        uint256 balance = pendingSellTax;
        delete pendingSellTax;
        IUniswapV2Pair pair = IUniswapV2Pair(
            IUniswapV2Factory(ROUTER.factory()).getPair(
                address(this),
                ROUTER.WETH()
            )
        );

        pair.sync();
        (uint256 rsv0, uint256 rsv1, ) = pair.getReserves();
        uint256 sellAmount = _calculateSwapInAmount(
            pair.token0() == address(this) ? rsv0 : rsv1,
            balance
        );

        ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        ROUTER.addLiquidityETH{value: address(this).balance}(
            address(this),
            balance - sellAmount,
            0,
            0,
            liquidityFeeReceiver,
            block.timestamp
        );
    }

    // use buy tax for marketing fee
    function _swapBuyTax() internal swapping {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = ROUTER.WETH();

        uint256 balance = pendingBuyTax;
        delete pendingBuyTax;

        uint256 balanceBefore = address(this).balance;

        ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            balance,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 marketingETH = address(this).balance - balanceBefore;
        (bool sent, ) = payable(marketingFeeReceiver).call{value: marketingETH}(
            ''
        );
        if (!sent) {
            revert FAIL_TO_SEND_ETH();
        }
    }

    function _calculateSwapInAmount(
        uint256 reserveIn,
        uint256 userIn
    ) internal view returns (uint256) {
        return
            (Babylonian.sqrt(
                reserveIn *
                    ((userIn * (uint256(4000) - (4 * uniswapFee)) * 1000) +
                        (reserveIn *
                            ((uint256(4000) - (4 * uniswapFee)) *
                                1000 +
                                uniswapFee *
                                uniswapFee)))
            ) - (reserveIn * (2000 - uniswapFee))) / (2000 - 2 * uniswapFee);
    }

    function _transferWithTax(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (inSwap) {
            _transfer(from, to, amount);
            return;
        }

        if (_shouldTakeSellTax(from, to)) {
            uint256 tax = (amount * taxInfo.liquidityFee) / MULTIPLIER;
            unchecked {
                amount -= tax;
                pendingSellTax += tax;
            }
            _transfer(from, address(this), tax);

            if (!inSwap && swapEnabled && pendingSellTax >= swapThreshold) {
                _swapSellTax();
            }
        }

        if (_shouldTakeBuyTax(from, to)) {
            uint256 tax = (amount * taxInfo.marketingFee) / MULTIPLIER;
            unchecked {
                amount -= tax;
                pendingBuyTax += tax;
            }
            _transfer(from, address(this), tax);
        } else {
            if (!inSwap && swapEnabled && pendingBuyTax >= swapThreshold) {
                _swapBuyTax();
            }
        }

        _transfer(from, to, amount);
    }
}
