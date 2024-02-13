# CoW AMM

> [!CAUTION]
> CoW AMM is a proof of concept of an AMM implemented on top of CoW Protocol.
> The code is not yet production ready and should not be used to handle large amounts of funds.
> For technical aspects of the smart contract, reach out to us on [discord](https://discord.com/invite/cowprotocol) as we push towards production, or simply star the repository to be informed of progress!

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

### Deployment addresses

The file [`networks.json`](./networks.json) lists all offical deployments of the contracts in this repository by chain id.

The deployment address file is generated with:
```sh
bash dev/generate-networks-file.sh > networks.json
```
