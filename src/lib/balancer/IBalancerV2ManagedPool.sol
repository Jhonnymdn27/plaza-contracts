// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IBalancerV2ManagedPool {
  function getVault() external view returns (address);

  function getScalingFactors() external view returns (uint256[] memory);

  function getNormalizedWeights() external view returns (uint256[] memory);

  function getPoolId() external view returns (bytes32);

  function totalSupply() external view returns (uint256);

  function getActualSupply() external view returns (uint256);
}
