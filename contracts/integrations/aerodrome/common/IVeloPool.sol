//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IVeloPool {
    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function stable() external view returns (bool);
}
