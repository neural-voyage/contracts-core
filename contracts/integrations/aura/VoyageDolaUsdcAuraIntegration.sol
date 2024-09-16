//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/VoyageAuraPoolIntegration.sol';

/// @title Voyage DOLA/USDC Aura integration
contract VoyageDolaUsdcAuraIntegration is VoyageAuraPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) VoyageAuraPoolIntegration(122, _oracle, _feeHandler) {}
}
