//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IBeefyVaultV7 {
    function want() external view returns (address);

    function getPricePerFullShare() external view returns (uint256);

    function deposit(uint _amount) external;

    function withdraw(uint256 _shares) external;
}
