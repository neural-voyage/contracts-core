//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IAuraBooster {
    function poolInfo(
        uint256
    ) external view returns (address, address, address, address, address, bool);

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);
}
