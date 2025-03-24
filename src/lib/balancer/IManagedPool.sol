// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IManagedPool {
  function getPoolId() external view returns (bytes32);
  function getNormalizedWeights() external view returns (uint256[] memory);
  function getScalingFactors() external view returns (uint256[] memory);
  function getActualSupply() external view returns (uint256);
}
