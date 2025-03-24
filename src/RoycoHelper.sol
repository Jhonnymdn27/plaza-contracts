// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Pool} from "./Pool.sol";
import {PreDeposit} from "./PreDeposit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RoycoHelper {
  using SafeERC20 for IERC20;

  function withdrawOrClaim(address preDepositAddress, address to, address token, uint256 amount) external {
    if (PreDeposit(preDepositAddress).poolCreated()) {
      address pool = PreDeposit(preDepositAddress).pool();
      address bondToken = address(Pool(pool).bondToken());
      address lToken = address(Pool(pool).lToken());

      uint256 bondTokenInitialBalance = IERC20(bondToken).balanceOf(address(this));
      uint256 lTokenInitialBalance = IERC20(lToken).balanceOf(address(this));

      PreDeposit(preDepositAddress).claimTo(msg.sender, to);

      uint256 bondTokenBalance = IERC20(bondToken).balanceOf(address(this));
      uint256 lTokenBalance = IERC20(lToken).balanceOf(address(this));

      if (bondTokenBalance - bondTokenInitialBalance > 0) {
        IERC20(bondToken).safeTransfer(to, bondTokenBalance - bondTokenInitialBalance);
      }

      if (lTokenBalance - lTokenInitialBalance > 0) {
        IERC20(lToken).safeTransfer(to, lTokenBalance - lTokenInitialBalance);
      }

      uint256 rejectedTokensCount = PreDeposit(preDepositAddress).getNumbRejectedTokens();
      for (uint256 i = 0; i < rejectedTokensCount; i++) {
        address _token = PreDeposit(preDepositAddress).rejectedTokens(i);
        if (token == address(0)) break;
        if (token == _token) {
          uint256 tokenInitialBalance = IERC20(token).balanceOf(address(this));

          PreDeposit(preDepositAddress).withdrawTo(msg.sender, to, token, amount);

          uint256 tokenBalance = IERC20(token).balanceOf(address(this));
          if (tokenBalance - tokenInitialBalance > 0) {
            IERC20(token).safeTransfer(to, tokenBalance - tokenInitialBalance);
          }
          break;
        }
      }
    } else {
      PreDeposit(preDepositAddress).withdrawTo(msg.sender, to, token, amount);
    }
  }
}
