use std::{cmp::min, collections::HashMap};

use alloy::{
    primitives::{Address, Bytes},
    providers::{Provider, ProviderBuilder},
    rpc::types::Filter,
    sol,
    sol_types::{SolEvent, SolValue},
};

// Codegen from ABI file to interact with the contract.
sol!(
    #[allow(missing_docs)]
    #[allow(clippy::too_many_arguments)]
    #[sol(rpc)]
    ComposableCoW,
    "../../abi/ComposableCoW.json"
);

#[tokio::main]
async fn main() -> eyre::Result<()> {
    const WINDOW_SIZE: u64 = 10000;
    const MAINNET_DEPLOYMENT_GENESIS: u64 = 19277205;
    const MAINNET_CONSTANT_PRODUCT_HANDLER: &str = "0x34323B933096534e43958F6c7Bf44F2Bb59424DA";
    const GNOSIS_DEPLOYMENT_GENESIS: u64 = 32478660;
    const GNOSIS_CONSTANT_PRODUCT_HANDLER: &str = "0xB148F40fff05b5CE6B22752cf8E454B556f7a851";

    let rpc_url = match std::env::var("RPC_URL") {
        Ok(url) => match url.parse() {
            Ok(url) => url,
            Err(_) => {
                eprintln!("Invalid URL: {}", url);
                std::process::exit(1);
            }
        },
        Err(_) => {
            eprintln!("Environment variable `RPC_URL` is not set");
            eprintln!("Usage: RPC_URL=<URL> indexer");
            std::process::exit(1);
        }
    };

    let provider = ProviderBuilder::new().on_http(rpc_url);

    // Determine the chain and then set the constant product handler and genesis block
    let chain_id = provider.get_chain_id().await?;
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
    let mut amms: HashMap<Address, Bytes> = HashMap::new();

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
                amms.insert(event.data.owner, event.params.abi_encode().into());
            }
        }

        latest_block = provider.get_block_number().await?;
        match latest_block == to_block {
            true => break,
            false => start_block = to_block + 1,
        }
    }

    println!("Total AMMs: {}", amms.len());
    println!("Caution: No guarantee is made that the AMMs will be presented in the same order as they were created.");
    amms.iter().for_each(|(k, v)| {
        println!("AMM: {},{}", k, v);
    });

    Ok(())
}
