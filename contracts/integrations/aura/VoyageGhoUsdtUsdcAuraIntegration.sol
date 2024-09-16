//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/VoyageAuraPoolIntegration.sol';

/// @title Voyage GHO/USDT/USDC Aura integration
contract VoyageGhoUsdtUsdcAuraIntegration is VoyageAuraPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) VoyageAuraPoolIntegration(157, _oracle, _feeHandler) {}
}
