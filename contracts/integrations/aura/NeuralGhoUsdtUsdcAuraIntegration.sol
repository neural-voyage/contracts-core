//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/NeuralAuraPoolIntegration.sol';

/// @title Neural GHO/USDT/USDC Aura integration
contract NeuralGhoUsdtUsdcAuraIntegration is NeuralAuraPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) NeuralAuraPoolIntegration(157, _oracle, _feeHandler) {}
}
