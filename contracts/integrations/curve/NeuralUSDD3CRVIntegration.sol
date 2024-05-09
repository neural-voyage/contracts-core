//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/curve/common/Neural3CRVMetaPoolIntegration.sol';

/// @title Neural USDD-3CRV pool integration
contract NeuralUSDD3CRVIntegration is Neural3CRVMetaPoolIntegration {
    /// @dev Meta pool specific addresses
    address private constant USDD_3CRV_POOL =
        0xe6b5CC1B4b47305c58392CE3D359B10282FC36Ea;
    address private constant USDD_3CRV_GAUGE =
        0xd5d3efC90fFB38987005FdeA303B68306aA5C624;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    )
        Neural3CRVMetaPoolIntegration(
            USDD_3CRV_POOL,
            USDD_3CRV_GAUGE,
            _oracle,
            _feeHandler
        )
    {}
}
