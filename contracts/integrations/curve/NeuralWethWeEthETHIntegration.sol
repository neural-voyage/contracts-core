//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/curve/common/NeuralCurveETHPoolIntegration.sol';

/// @title Neural FRAX-3CRV pool integration
contract NeuralWethWeEthETHIntegration is NeuralCurveETHPoolIntegration {
    /// @dev Meta pool specific addresses
    address private constant POOL = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;
    address private constant GAUGE = 0x053df3e4D0CeD9a3Bf0494F97E83CE1f13BdC0E2;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    ) NeuralCurveETHPoolIntegration(POOL, GAUGE, _oracle, _feeHandler) {}
}
