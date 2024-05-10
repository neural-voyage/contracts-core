//SPDX-License-Identifier: Unlicense

pragma solidity =0.8.9;

interface IAuraRewards {
    function withdrawAndUnwrap(
        uint256 amount,
        bool claim
    ) external returns (bool);

    function getReward(
        address _account,
        bool _claimExtras
    ) external returns (bool);
}
