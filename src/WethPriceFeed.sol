// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract WethPriceFeed is AggregatorV3Interface {
  error NotImplemented();

  /**
   * @dev Returns the decimals of the WETH price feed.
   * @return uint8 The decimals.
   */
  function decimals() external pure returns (uint8) {
    return 18;
  }

  /**
   * @dev Returns the description of the WETH price feed.
   * @return string The description.
   */
  function description() external pure returns (string memory) {
    return "WETH Price Feed";
  }

  /**
   * @dev Returns the version of the WETH price feed.
   * @return uint256 The version.
   */
  function version() external pure returns (uint256) {
    return 1;
  }

  /**
   * @dev Not implemented.
   */
  function getRoundData(uint80 /*_roundId*/ ) public pure returns (uint80, int256, uint256, uint256, uint80) {
    revert NotImplemented();
  }

  /**
   * @dev This is dummy price feed that returns a constant price of 1 ether.
   * BalancerOracleAdapter expects each token in the balancer pool to have a price feed denominated
   * in ETH
   * @return uint80 The round ID.
   * @return int256 The price.
   * @return uint256 The started at timestamp.
   * @return uint256 The updated at timestamp.
   * @return uint80 The answered in round.
   */
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, 1 ether, block.timestamp, block.timestamp, 0);
  }
}
