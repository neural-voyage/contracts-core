//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/aura/common/VoyageAuraETHPoolIntegration.sol';

/// @title Voyage DOLA/USDC Aura integration
contract VoyageWethEzEthAuraETHIntegration is VoyageAuraETHPoolIntegration {
    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) VoyageAuraETHPoolIntegration(189, _oracle, _feeHandler) {}
}
