//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}
