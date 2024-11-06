//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

import 'contracts/integrations/curve/common/Voyage3CRVMetaPoolIntegration.sol';

/// @title Voyage MIM-3CRV pool integration
contract VoyageMIM3CRVIntegration is Voyage3CRVMetaPoolIntegration {
    /// @dev Meta pool specific addresses
    address private constant MIM_3CRV_POOL =
        0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address private constant MIM_3CRV_GAUGE =
        0xd8b712d29381748dB89c36BCa0138d7c75866ddF;

    /// @param _oracle Oracle address
    /// @param _feeHandler Fee handler address
    constructor(
        address _oracle,
        address _feeHandler
    )
        Voyage3CRVMetaPoolIntegration(
            MIM_3CRV_POOL,
            MIM_3CRV_GAUGE,
            _oracle,
            _feeHandler
        )
    {}
}