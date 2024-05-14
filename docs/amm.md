# CoW AMM

CoW AMM is an automated market maker running on top of CoW Protocol.

## Overview

The CoW AMM is a contract that stores reserves of two tokens and allows anyone to create orders between these two tokens on CoW Protocol as long as the trade doesn't decrease the product of the reserves stored on the contract.

If created through the dedicated factory, the AMM creates a CoW Protocol order at a regular time interval.
These orders are created with a dedicated contract function `getTradeableOrderWithSignature`: it returns an order that can be traded in a way that tries to rebalance the AMM to align with the reference price of a price oracle.
These orders are provided for convenience to CoW Swap solvers so that basic CoW AMM usage does not need any dedicated implementation to tap into its liquidity.
More sophisticated solvers can create their own order to better suit the current market conditions.

The [watch tower](https://github.com/cowprotocol/watch-tower) is responsible for automatically creating the AMM order, without any necessity for the AMM to interact with the CoW Protocol API.

CoW AMM orders are executed in batches by CoW Protocol solvers.
Only one order per AMM can be executed per batch.

Further information on the theoretical research work that serves as the base of CoW AMM can be found in the paper [Arbitrageurs' profits, LVR, and sandwich attacks: batch trading as an AMM design response](https://arxiv.org/pdf/2307.02074.pdf).

Batch trading guarantees that despite the minimum viable order follows the constant-product curve (as it's the case for Uniswap v2) the surplus captured by CoW Protocol yields to a better execution price and thus higher profits for liquidity providers.

## Limitations

The current setup doesn't support pooling liquidity among different users at this point in time.
A new CoW AMM instance needs to be deployed every time a user wants to provide liquidity for a pair.
Native tokens must be wrapped before using them as a token in the pair.

## Supported price oracles

Price oracles are an abstraction that transform disparate on-chain price information into a standardized price source that can be used by the `ConstantFroduct` to retrieve token price information.

We support the following price oracles:
- `UniswapV2PriceOracle`, based on the limit price of a predefined Uniswap v2 pair.

Contract addresses for each supported chain can be found in the file `networks.json`.

### UniswapV2PriceOracle

The Uniswap v2 price oracle returns the limit price that can be computed from an address (pool) that supports the `IUniswapV2Pair` interface.
The oracle data contains a single parameter:
- `IUniswapV2Pair referencePair`: the address of a Uniswap pool for the tokens `token0` and `token1`.

Note that the order of the tokens does _not_ need to be consistent with the order of the tokens in the pool.
The order of the tokens in the AMM determines that the price is expressed in terms of amount of token0 per amount of token1.
If the tokens are not the same as those traded on the chosen reference pair, no order will be created.

If Foundry is available in your system, you can generate the bytes calldata with the following command:
```sh
referencePair=0x1111111111111111111111111111111111111111
cast abi-encode 'f((address))' "($referencePair)"
```

### BalancerWeightedPoolPriceOracle

The Balancer weighted pool price oracle returns the limit price that can be computed from one of the [Balancer weighted pool](https://docs.balancer.fi/concepts/pools/weighted.html) implementations.

The oracle data contains a single parameter:
- `bytes32 poolId`: the [Balancer pool id](https://docs.balancer.fi/reference/contracts/pool-interfacing.html#poolids) representing the weighted pool that will be used to compute the reference price.

The reference weighted pool can use any weights and token combination.
However, it must be a weighted pool and not a different pool type: there is currently no check in the smart contract to guarantee that the chosen pool is indeed a weighted pool. If used with a different type of pool, the output of the oracle is likely to be completely unreliable.

If the tokens in the AMM orders are not all included in the reference pool, then no order will be created.

If Foundry is available in your system, you can generate the bytes calldata with the following command:
```sh
poolId=0x1111111111111111111111111111111111111111111111111111111111111111
cast abi-encode 'f((bytes32))' "($poolId)"
```

### ChainlinkPriceOracle

The Chainlink price oracle returns the limit price from reading two [Chainlink Data Feed](https://docs.chain.link/data-feeds/price-feeds/addresses).

The oracle data contains four parameters:
- `address token0Feed`: Address of Chainlink price oracle for token0
- `address token1Feed`: Address of Chainlink price oracle for token1
- `uint256 timeThreshold`: Amount of seconds before the oracle is considered stale
- `uint256 backoff`: Amount of seconds for watch tower to wait before retrying from stale oracle.
s
While this oracle is intended to support Chainlink Data Feed, it can also read from any contract that implement `AggregatorV3` interface, as long as `decimals` in the feed is less than 18. The contract will handle decimals scaling automatically (such as AMPL/USD with 18 decimals). There is no check for token to corresponds with the feed address. The users will have to check for correctness by themselves.

Some feed like Forex and commodity pair will not avaliable outside their market hours. Consider setting `2 days` as backoff duration for those address.

If Foundry is available in your system, you can generate the bytes calldata with the following command:
```sh
token0Feed=0x1111111111111111111111111111111111111111
token1Feed=0x2222222222222222222222222222222222222222
timeThreshold=86400
backoff=172800
cast abi-encode 'f((address, address, uint256, uint256))' "($token0Feed, $token1Feed, $timeThreshold, $backoff)"
```

## Contract code verification on block explorer

You can verify an AMM created from the factory with the following commands:
```sh
export ETH_RPC_URL='https://your.rpc.node.here'
export ETHERSCAN_API_KEY='YOUR-BLOCK-EXPLORER-API-KEY'
amm='0xaddress-to-verify'
# end customizable part
token0=$(cast call "$amm" 'token0()(address)')
token1=$(cast call "$amm" 'token1()(address)')
constructor_args=$(cast abi-encode 'constructor(address,address,address)' 0x9008d19f58aabd9ed0d60971565aa8510560ab41 "$token0" "$token1")
forge verify-contract "$amm" 'src/ConstantProduct.sol:ConstantProduct' --watch --constructor-args "$constructor_args"
```

## I'm a solver. How do I use CoW AMM liquidity?

CoW AMM orders already appear in the CoW Protocol orderbook, so you're already using its liquidity.
However, CoW AMMs allow solvers to specify custom buy and sell amounts, as long as the order preserves or increase the constant product invariant of the token reserves. 

CoW AMMs can be treated as a liquidity source akin to Uniswap or Balancer weighted pools with uniform weights.
Each CoW AMM is a pair that trades two tokens.

Importantly, surplus for a CoW AMM order is measured differently when computing the solver reward payout.

### Listing all CoW AMMs

Every supported chain has an official factory contract, specified in the file `networks.json`.

The creation of new AMMs emits a `Deployed` event from the factory, which lists the AMM address, its owner, and the traded tokens.
Owner and traded tokens will never change for the AMM identified by that address.
No AMM created by the factory can trade more than a single pair of tokens.

Every time a CoW AMM becomes available for trading on CoW Swap, the factory emits an event `ComposableCoW.ConditionalOrderCreated` with the AMM address and the ABI-encoded trading parameters.
This event is fired both for newly deployed AMMs and for CoW AMMs whose trading has been re-enabled after having had been disabled.
Unlike the AMM deployment parameters, trading parameters _can_ change during the lifetime of the AMM.
However, at any point in time there can be at most one set of valid trading parameters.

Trading can be disabled at any point in time by the owner.
Disabiling trading causes the emission of an event `TradingDisabled` that indicates the address of the disabled AMM.

### Settling a custom order

You need to choose a valid CoW Swap order with the following restrictions:

- `sellToken`: any token in the pair.
- `buyToken`: the other token in the pair.
- `receiver`: must be `RECEIVER_SAME_AS_OWNER` (zero address).
- `sellAmount`: any value.
- `buyAmount`: any value such that, after trading these exact amounts, the product of the token reserves is no smaller than before trading.
- `validTo`: at most 5 minutes after the block timestamp at execution time.
- `appData`: must be the value specified in `tradingParams`.
- `feeAmount`: must be zero.
- `kind`: any value.
- `partiallyFillable`: any value.
- `sellTokenBalance`: must be `BALANCE_ERC20`.
- `buyTokenBalance`: must be `BALANCE_ERC20`.

You also need to compute:
- the order hash `hash` as defined in the library `GPv2Order`, and
- the order signature (`abi.encode(order, tradingParams)`, where `order` is the order parameters in the `GPv2Order.Data` format and `tradingParams` are the currently enabled trading parameters as indicated by the latest fired event `ComposableCoW.ConditionalOrderCreated`).

This order can be included in a batch as any other CoW Protocol orders with two extra conditions:
- A pre-interaction must set the commitment by calling `ConstantProduct.commit(hash)`.
- The batch must contain at most one order from the same AMM.

#### Signature encoding example

If Foundry is available in your system, you can generate the signature bytes with the following command:
```sh
sellToken='0xaa111111111111111111111111111111111111aa'
buyToken='0xaa222222222222222222222222222222222222aa'
receiver='0x0000000000000000000000000000000000000000'
sellAmount='333'
buyAmount='444'
validTo='555'
appData='0x6666666666666666666666666666666666666666666666666666666666666666'
feeAmount='0'
kind='f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775' # sell
partiallyFillable='true'
sellTokenBalance='5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9' # erc20
buyTokenBalance='5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9' # erc20
minTradedToken0='777'
priceOracle='0xaa888888888888888888888888888888888888aa'
priceOracleData='0x9999'
cast abi-encode 'f((address,address,address,uint256,uint256,uint32,bytes32,uint256,bytes32,bool,bytes32,bytes32),(uint256,address,bytes,bytes32))' "($sellToken,$buyToken,$receiver,$sellAmount,$buyAmount,$validTo,$appData,$feeAmount,$kind,$partiallyFillable,$sellTokenBalance,$buyTokenBalance)" "($minTradedToken0,$priceOracle,$priceOracleData,$appData)"
```

## Risk profile

The risks for the funds on the AMM are comparable to the risks of depositing the same reserves on a constant-product curve like Uniswap v2.

The AMM relies on price oracle exclusively for generating orders that will plausibly be settled in the current market conditions, but they aren't used to determine whether an order is valid.
If a price oracle is compromised or manipulated, the main risk is that the liquidity available on CoW protocol will be used suboptimally by the solvers that aren't aware of the custom semantics of a CoW AMM.
