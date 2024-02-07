## CoW AMM

CoW AMM is an automated market maker running on top of CoW Protocol.

## Documentation

You can find detailed documentation on the building blocks of this repo in the following files:

- [amm.md](./docs/amm.md): details on what a CoW AMM is and how to set it up.

## Research

Details on the theory behind CoW AMM can be found on the paper [Arbitrageurs' profits, LVR, and sandwich attacks: batch trading as an AMM design response](https://arxiv.org/pdf/2307.02074.pdf).

## Development

### Dev set up

You can install git hooks to help you catch simple mistakes before running some git actions like committing.
See the [dedicated instructions](./dev/hooks/install.md) for how to install the hooks.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy

All contracts in this repo can be deployed and verified on the block explorer as follows:

```sh
export ETHERSCAN_API_KEY='your API key here'
PK='the private key of the deployer'
ETH_RPC_URL='https://rpc.node.url.here.example.com'
forge script 'script/DeployAllContracts.s.sol:DeployAllContracts' -vvvv --rpc-url "$ETH_RPC_URL" --private-key "$PK" --verify --broadcast
```