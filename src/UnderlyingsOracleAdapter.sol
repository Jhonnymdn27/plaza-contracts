// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Decimals} from "./lib/Decimals.sol";
import {OracleReader} from "./OracleReader.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract UnderlyingsOracleAdapter is Initializable, AggregatorV3Interface, OracleReader {
  using Decimals for uint256;

  address public tokenAddress;
  uint8 public decimals;

  error NotImplemented();
  error PriceTooLargeForIntConversion();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _tokenAddress, uint8 _decimals, address _oracleFeeds) external initializer {
    __OracleReader_init(_oracleFeeds);
    tokenAddress = _tokenAddress;
    decimals = _decimals;
  }

  function description() external pure returns (string memory) {
    return "Token to USD Price Feed";
  }

  function version() external pure returns (uint256) {
    return 1;
  }

  function getRoundData(uint80)
    public
    pure
    returns (uint80, int256, uint256, uint256, uint80)
  {
    revert NotImplemented();
  }

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    uint256 tokenEthPrice = getOraclePrice(tokenAddress, ETH);
    uint8 tokenEthDecimals = getOracleDecimals(tokenAddress, ETH);

    uint256 ethUsdPrice = getOraclePrice(ETH, USD);
    uint8 ethUsdDecimals = getOracleDecimals(ETH, USD);

    uint256 usdPrice = (tokenEthPrice * ethUsdPrice).normalizeAmount(tokenEthDecimals + ethUsdDecimals, decimals);

    if (usdPrice > uint256(type(int256).max)) revert PriceTooLargeForIntConversion();

    return (0, int256(usdPrice), block.timestamp, block.timestamp, 0);
  }
}
