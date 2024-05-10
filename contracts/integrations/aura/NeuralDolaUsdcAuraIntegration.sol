//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/NeuralAuraPoolIntegration.sol';

/// @title Neural DOLA/USDC Aura integration
contract NeuralDolaUsdcAuraIntegration is NeuralAuraPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) NeuralAuraPoolIntegration(122, _oracle, _feeHandler) {}
}
