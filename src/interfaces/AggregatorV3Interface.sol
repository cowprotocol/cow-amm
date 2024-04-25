// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Chainlink Oracle Interface
 * @dev This interface is from <https://github.com/smartcontractkit/chainlink/blob/7ec1d5b7abb51e100f7a6a48662e33703a589ecb/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol>
 */
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}