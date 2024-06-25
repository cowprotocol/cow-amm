use std::{cmp::min, collections::HashMap};

use alloy::{
    hex,
    primitives::{keccak256, Address},
    providers::{Provider, ProviderBuilder},
    rpc::types::Filter,
    sol_types::{SolEvent, SolValue},
};
use cow_amm_common::{
    rpc_url,
    ComposableCoW::{self, ConditionalOrderParams},
    LegacyTradingParams, IERC20,
};

#[tokio::main]
async fn main() -> eyre::Result<()> {
    const WINDOW_SIZE: u64 = 10000;
    const MAINNET_DEPLOYMENT_GENESIS: u64 = 19277205;
    const MAINNET_CONSTANT_PRODUCT_HANDLER: &str = "0x34323B933096534e43958F6c7Bf44F2Bb59424DA";
    const GNOSIS_DEPLOYMENT_GENESIS: u64 = 32478660;
    const GNOSIS_CONSTANT_PRODUCT_HANDLER: &str = "0xB148F40fff05b5CE6B22752cf8E454B556f7a851";
    const COMPOSABLE_COW: &str = "0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74";

    // Create a provider.
    let provider = ProviderBuilder::new().on_http(rpc_url());

    // Determine the chain and then set the constant product handler and genesis block
    let chain_id = provider.get_chain_id().await?;
    println!("Chain ID: {}", chain_id);

    let (constant_product_handler, mut start_block): (Address, u64) = match chain_id {
        1 => (
            MAINNET_CONSTANT_PRODUCT_HANDLER.parse()?,
            MAINNET_DEPLOYMENT_GENESIS,
        ),
        100 => (
            GNOSIS_CONSTANT_PRODUCT_HANDLER.parse()?,
            GNOSIS_DEPLOYMENT_GENESIS,
        ),
        _ => {
            return Err(eyre::eyre!("Unsupported chain ID: {}", chain_id));
        }
    };

    let mut latest_block = provider.get_block_number().await?;
    let mut amms: HashMap<Address, ConditionalOrderParams> = HashMap::new();

    loop {
        let to_block = start_block + min(WINDOW_SIZE - 1, latest_block - start_block);
        let filter = Filter::new()
            .event(ComposableCoW::ConditionalOrderCreated::SIGNATURE)
            .from_block(start_block)
            .to_block(to_block);
        println!("Processing blocks: {} - {}", start_block, to_block);

        // Get all logs from the latest block that match the filter.
        let logs = provider.get_logs(&filter).await?;

        // Iterate over the logs, only concerned about `ConstantProduct` handlers
        for log in logs {
            let event =
                ComposableCoW::ConditionalOrderCreated::decode_log(&log.inner, true).unwrap();

            if event.data.params.handler == constant_product_handler {
                // insert will override the previous value if the key already existed
                amms.insert(event.data.owner, event.params.clone());
            }
        }

        latest_block = provider.get_block_number().await?;
        match latest_block == to_block {
            true => break,
            false => start_block = to_block + 1,
        }
    }

    // Filter out AMMs that are no longer open
    let composable_cow = ComposableCoW::new(COMPOSABLE_COW.parse().unwrap(), provider.clone());
    let amms = futures_util::future::join_all(amms.iter().map(|(addr, params)| {
        let composable_cow = composable_cow.clone();
        let provider = provider.clone();
        async move {
            let trading_enabled = composable_cow
                .singleOrders(*addr, keccak256(params.abi_encode()))
                .call()
                .await
                .unwrap()
                ._0;

            if !trading_enabled {
                return None;
            }

            // Decode the staticInput as LegacyTradingParams
            let static_input = LegacyTradingParams::abi_decode(&params.staticInput, true).unwrap();

            for token in [&static_input.token0, &static_input.token1] {
                let balance = IERC20::new(token.clone(), provider.clone())
                    .balanceOf(*addr)
                    .call()
                    .await
                    .unwrap()
                    ._0;

                if balance.is_zero() {
                    return None;
                }
            }

            Some((addr, params))
        }
    }))
    .await
    .into_iter()
    .flatten()
    .collect::<HashMap<_, _>>();

    println!("\nTotal open AMMs: {}", amms.len());
    println!("\nWill now print the AMMs in the format: <AMM Address>,<AMM Bytes Params>");
    println!("Please note that the AMM Bytes Params are ABI encoded and will need to be decoded to be human readable.\n");
    println!("Caution: No guarantee is made that the AMMs will be presented in the same order as they were created.\n");
    amms.iter().for_each(|(k, v)| {
        println!("{},{}", k, hex::encode(v.abi_encode()));
    });

    Ok(())
}
