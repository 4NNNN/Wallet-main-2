//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IModuleManager {
    function getModule(uint256 _id) external view returns (address, address);
    function isAuthorizedModule(address module) external view returns (bool);
    function accountRegistry() external view returns (address);
}
