//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint amount) external;
}
