// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Pool} from "./Pool.sol";
import {PreDeposit} from "./PreDeposit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RoycoHelper {
  using SafeERC20 for IERC20;

  function withdrawOrClaim(address preDepositAddress, address to, address token, uint256 amount) external {
    PreDeposit preDeposit = PreDeposit(preDepositAddress);
    if (preDeposit.poolCreated()) {
      preDeposit.claimTo(msg.sender, to);

      uint256 rejectedAmount = preDeposit.balances(msg.sender, token);
      if (rejectedAmount > 0) {
        preDeposit.withdrawTo(msg.sender, to, token, rejectedAmount);
      }
    } else {
      preDeposit.withdrawTo(msg.sender, to, token, amount);
    }
  }
}
