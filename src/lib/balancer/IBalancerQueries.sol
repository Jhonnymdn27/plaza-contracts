// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IVault} from "@balancer/contracts/interfaces/contracts/vault/IVault.sol";

interface IBalancerQueries {
  function queryJoin(bytes32 poolId, address sender, address recipient, IVault.JoinPoolRequest memory request)
    external
    returns (uint256 bptOut, uint256[] memory amountsIn);

  function queryExit(bytes32 poolId, address sender, address recipient, IVault.ExitPoolRequest memory request)
    external
    returns (uint256 bptIn, uint256[] memory amountsOut);
}
