// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAsset} from "@balancer/contracts/interfaces/contracts/vault/IAsset.sol";

struct ManagedPoolParams {
  string name;
  string symbol;
  address[] assetManagers;
}

struct ManagedPoolSettingsParams {
  IAsset[] tokens;
  uint256[] normalizedWeights;
  uint256 swapFeePercentage;
  bool swapEnabledOnStart;
  bool mustAllowlistLPs;
  uint256 managementAumFeePercentage;
  uint256 aumFeeId;
}

interface IManagedPoolFactory {
  function create(
    ManagedPoolParams memory params,
    ManagedPoolSettingsParams memory settingsParams,
    address owner,
    bytes32 salt
  ) external returns (address pool);
}
