#![feature(async_closure)]
use cow_amm_common::{
    rpc_url, ComposableCoW,
    ConstantProductHelper::{self, ConstantProductHelperErrors},
    GPv2Settlement,
    IConstantProductHelper::{self, dReturn},
    IMulticall3, IPriceOracle, LegacyTradingParams, Order, IERC1271,
};
use std::collections::HashMap;

use std::str::FromStr;

use alloy::{
    contract::Error,
    hex,
    primitives::{Address, Bytes},
    providers::{Provider, ProviderBuilder},
    rpc::types::state::AccountOverride,
    sol_types::{
        decode_revert_reason, eip712_domain, SolCall, SolEvent, SolInterface, SolStruct, SolValue,
    },
    transports::TransportError,
};

#[tokio::main]
async fn main() -> eyre::Result<()> {
    const SETTLEMENT: &str = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41";
    const MUTLICALL3: &str = "0xcA11bde05977b3631167028862bE2a173976CA11";

    // Create a provider.
    let provider = ProviderBuilder::new().on_http(rpc_url());
    let chain_id = provider.get_chain_id().await?;

    // Which amm are we interested in?
    let amm: Address = match std::env::var("AMM") {
        Ok(amm) => match amm.parse() {
            Ok(amm) => amm,
            Err(_) => {
                eprintln!("Invalid AMM: {}", amm);
                std::process::exit(1);
            }
        },
        Err(_) => {
            eprintln!("Environment variable `AMM` is not set");
            eprintln!("Usage: RPC_URL=<URL> AMM=<AMM> poller");
            std::process::exit(1);
        }
    };

    println!("Polling AMM: {:?}", amm);

    // First configure the helper and the overrides
    const HELPER: &str = "0xBEEF5AFeBEef5aFeBEeF5AfEBEef5AfEBEef5AFE";
    let helper = ConstantProductHelper::new(HELPER.parse()?, provider.clone());
    let mut overrides = HashMap::new();
    overrides.insert(
        HELPER.parse()?,
        AccountOverride {
            code: Some(ConstantProductHelper::DEPLOYED_BYTECODE.clone()),
            ..Default::default()
        },
    );

    // Second get the raw data that comes from the snapshot within the ConstantProductHelper
    // This is needed so that we can lookup an oracle, unless we otherwise have the price to
    // supply.
    let data = helper
        .getSnapshot(amm)
        .state(overrides.clone())
        .call()
        .await?;

    // Third decode the data and get the trading params
    let (data,) = ComposableCoW::ConditionalOrderCreated::abi_decode_data(&data._0, true).unwrap();
    let trading_params = LegacyTradingParams::abi_decode(&data.staticInput, true).unwrap();

    // Fourth, let's get the price from the oracle
    let oracle_price = IPriceOracle::new(trading_params.priceOracle, provider.clone())
        .getPrice(
            trading_params.token0,
            trading_params.token1,
            trading_params.priceOracleData,
        )
        .call()
        .await
        .unwrap();

    println!(
        "Oracle Price: {:?} / {:?}",
        oracle_price.priceNumerator, oracle_price.priceDenominator
    );

    // Fifth, we now have relative prices, so we can use the helper to get the order
    let hint = helper
        .order(
            amm,
            vec![oracle_price.priceNumerator, oracle_price.priceDenominator],
        )
        .state(overrides)
        .call_raw()
        .await
        .map_or_else(Err, |d| {
            let dReturn {
                order,
                interactions,
                sig,
            } = IConstantProductHelper::dCall::abi_decode_returns(&d, true).unwrap();
            Ok((order, interactions, sig))
        });

    // Sixth, use the hint and verify that it can be settled on-chain. This is done by:
    // 1. Using `simulateDelegateCall` from the settlement contract to the `Multicall3` as we need to call two functions
    // 2. The first function is the interaction, which is the `commit` function on the AMM
    // 3. The second function is the `isValidSignature` function on the AMM that would otherwise be called
    //    normally during the course of the settlement process
    // 4. We will then verify that the `isValidSignature` function returns valid

    match hint {
        Ok((order, interactions, sig)) => {
            println!("\nHint received!");
            println!("Order: {:?}", order);
            println!("Interactions: {:?}", interactions.clone());
            println!("Sig: {:?}", sig);

            let offchain_order = Order::try_from(order).unwrap();

            let domain = eip712_domain! {
                name: "Gnosis Protocol",
                version: "v2",
                chain_id: chain_id,
                verifying_contract: SETTLEMENT.parse()?,
            };

            let signing_message = offchain_order.eip712_signing_hash(&domain);

            // To do this, we will make use of Multicall3
            let payload = IMulticall3::tryAggregateCall {
                requireSuccess: true,
                calls: vec![
                    IMulticall3::Call {
                        target: interactions[0].target,
                        callData: interactions[0].callData.clone(),
                    },
                    IMulticall3::Call {
                        target: amm,
                        callData: IERC1271::isValidSignatureCall {
                            _hash: signing_message,
                            signature: sig,
                        }
                        .abi_encode()
                        .into(),
                    },
                ],
            }
            .abi_encode();
            println!(
                "\nsimulateDelegateCall payload: {:?}",
                hex::encode(payload.clone())
            );

            let settlement = GPv2Settlement::new(SETTLEMENT.parse().unwrap(), provider.clone());
            let result = settlement
                .simulateDelegatecall(MUTLICALL3.parse().unwrap(), payload.into())
                .call()
                .await;

            match result {
                Ok(result) => {
                    println!("\nSuccess!\n{:?}", result);
                }
                Err(e) => {
                    println!("Error: {:?}", e);
                }
            }
        }
        Err(Error::TransportError(TransportError::ErrorResp(err))) => {
            let data = err.data.unwrap_or_default();
            let data = data.get().trim_matches('"');
            let data = Bytes::from_str(data).unwrap();
            println!("Data: {:?}", data);
            let decoded_error = ConstantProductHelperErrors::abi_decode(&data, true);

            match decoded_error {
                Ok(t) => match t {
                    ConstantProductHelperErrors::PoolDoesNotExist(_) => {
                        println!("Pool does not exist: {:?}", amm);
                    }
                    ConstantProductHelperErrors::PoolIsClosed(_) => {
                        println!("Pool is closed: {:?}", amm);
                    }
                    _ => {}
                },
                Err(e) => match decode_revert_reason(&data) {
                    Some(reason) => {
                        println!("Reason: {:?}", reason);
                    }
                    None => {
                        println!("Err: {:?}", e);
                    }
                },
            }
        }
        Err(e) => {
            println!("Error: {:?}", e);
        }
    }

    Ok(())
}
