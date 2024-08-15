//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/NeuralAuraETHPoolIntegration.sol';

/// @title Neural DOLA/USDC Aura integration
contract NeuralWethEzEthAuraETHIntegration is NeuralAuraETHPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) NeuralAuraETHPoolIntegration(189, _oracle, _feeHandler) {}
}
