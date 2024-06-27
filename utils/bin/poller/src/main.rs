use cow_amm_common::{
    rpc_url, ComposableCoW,
    ConstantProductHelper::{self, ConstantProductHelperErrors},
    GPv2Settlement,
    IConstantProductHelper::{self, dReturn, Interaction},
    IMulticall3, IPriceOracle, LegacyConstantProduct, LegacyTradingParams, Order, IERC1271,
};
use std::collections::HashMap;

use eyre::Result;

use std::str::FromStr;

use alloy::{
    contract::Error,
    hex,
    primitives::{Address, Bytes, FixedBytes, U256},
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
    const MULTICALL3: &str = "0xcA11bde05977b3631167028862bE2a173976CA11";

    // Create a provider.
    let provider = ProviderBuilder::new().on_http(rpc_url());
    let chain_id = provider.get_chain_id().await?;

    // Which amm are we interested in?
    let amm: Address = std::env::var("AMM")
        .expect("Environment variable `AMM` is not set")
        .parse()
        .expect("Invalid address specified for AMM");

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

    // Check if the AMM is legacy
    let legacy = !data._0.is_empty();

    let numerator = std::env::var("NUMERATOR");
    let denominator = std::env::var("DENOMINATOR");

    // Here we determine the numerator / denominator, as well as the commitment read address
    // The committment read address changes between legacy and non-legacy AMMs
    // (Legacy is within the ConstantProduct *handler* field, non-legacy is the AMM address itself)
    let (numerator, denominator, commitment_read_address) = match legacy {
        true => {
            // Third decode the data and get the trading params
            let (data,) =
                ComposableCoW::ConditionalOrderCreated::abi_decode_data(&data._0, true).unwrap();
            let trading_params = LegacyTradingParams::abi_decode(&data.staticInput, true).unwrap();

            let (numerator, denominator) = match (numerator, denominator) {
                (Ok(n), Ok(d)) => (U256::from_str(&n)?, U256::from_str(&d)?),
                (Ok(_), _) | (_, Ok(_)) => {
                    return Err(eyre::eyre!(
                        "Must not set just one of NUMERATOR and DENOMINATOR"
                    ))
                }
                _ => {
                    let oracle_price =
                        IPriceOracle::new(trading_params.priceOracle, provider.clone())
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
                    (oracle_price.priceNumerator, oracle_price.priceDenominator)
                }
            };

            (numerator, denominator, data.handler)
        }
        false => match (numerator, denominator) {
            (Ok(n), Ok(d)) => (U256::from_str(&n)?, U256::from_str(&d)?, amm),
            _ => {
                return Err(eyre::eyre!(
                    "NUMERATOR and DENOMINATOR env vars must be set for non-legacy AMMs"
                ))
            }
        },
    };

    // Fifth, we now have relative prices, so we can use the helper to get the order
    let hint = helper
        .order(amm, vec![numerator, denominator])
        .state(overrides)
        .call_raw()
        .await
        .map_or_else(Err, |d| {
            let dReturn {
                order,
                preInteractions,
                postInteractions,
                sig,
            } = IConstantProductHelper::dCall::abi_decode_returns(&d, true).unwrap();
            Ok((order, preInteractions, postInteractions, sig))
        });

    // Sixth, use the hint and verify that it can be settled on-chain. This is done by:
    // 1. Using `simulateDelegateCall` from the settlement contract to the `Multicall3` as we need to call two functions
    // 2. The first function is the interaction, which is the `commit` function on the AMM
    // 3. The second function is the `isValidSignature` function on the AMM that would otherwise be called
    //    normally during the course of the settlement process
    // 4. We will then verify that the `isValidSignature` function returns valid

    let (order, pre_interactions, post_interactions, sig) = hint.map_err(|e| {
        eyre::eyre!(match e {
            Error::TransportError(TransportError::ErrorResp(err)) => {
                let data = err.data.unwrap_or_default();
                let data = data.get().trim_matches('"');
                let data = Bytes::from_str(data).unwrap();
                println!("Data: {:?}", data);
                let decoded_error = ConstantProductHelperErrors::abi_decode(&data, true);

                match decoded_error {
                    Ok(t) => match t {
                        ConstantProductHelperErrors::PoolDoesNotExist(_) => {
                            format!("Pool does not exist: {:?}", amm)
                        }
                        ConstantProductHelperErrors::PoolIsClosed(_) => {
                            format!("Pool is closed: {:?}", amm)
                        }
                        _ => format!("Unspecified ConstantProductHelperErrors"),
                    },
                    Err(e) => match decode_revert_reason(&data) {
                        Some(reason) => format!("Reason: {:?}", reason),
                        None => format!("Err: {:?}", e),
                    },
                }
            }
            e => format!("Error: {:?}", e),
        })
    })?;

    println!("\nHint received!");
    println!("Order: {:?}", order);
    println!("Pre Interactions: {:?}", pre_interactions.clone());
    println!("Post Interactions: {:?}", post_interactions.clone());
    println!("Sig: {:?}", sig);

    let offchain_order = Order::try_from(order).unwrap();

    let domain = eip712_domain! {
        name: "Gnosis Protocol",
        version: "v2",
        chain_id: chain_id,
        verifying_contract: SETTLEMENT.parse()?,
    };

    let signing_message = offchain_order.eip712_signing_hash(&domain);

    // stash the number of interactions so map_interactions can consume the slice
    let num_pre_interactions = pre_interactions.len();
    let num_post_interactions = post_interactions.len();

    // To do this, we will make use of Multicall3
    let calls = [
        map_interactions(pre_interactions.clone())?,
        vec![IMulticall3::Call {
            target: amm,
            callData: IERC1271::isValidSignatureCall {
                _hash: signing_message,
                signature: sig,
            }
            .abi_encode()
            .into(),
        }],
        map_interactions(post_interactions.clone())?,
        // read the commitment after the post interactions
        vec![IMulticall3::Call {
            target: commitment_read_address,
            callData: LegacyConstantProduct::commitmentCall {
                amm: commitment_read_address,
            }
            .abi_encode()
            .into(),
        }],
    ]
    .concat();

    let payload = IMulticall3::tryAggregateCall {
        requireSuccess: true,
        calls,
    }
    .abi_encode();
    println!(
        "\nsimulateDelegateCall payload: {:?}",
        hex::encode(payload.clone())
    );

    let settlement = GPv2Settlement::new(SETTLEMENT.parse().unwrap(), provider.clone());
    let result = settlement
        .simulateDelegatecall(MULTICALL3.parse().unwrap(), payload.into())
        .call()
        .await;

    let result = result.map_err(|e| eyre::eyre!("Error: {:?}", e))?;

    let response = IMulticall3::tryAggregateCall::abi_decode_returns(&result.response, true)?;

    // Check that all calls were successful
    response.returnData[0..num_pre_interactions]
        .iter()
        .for_each(|r| {
            assert!(r.success, "Pre interaction Call failed");
        });

    // Check that the signature was correct
    assert!(response.returnData[num_pre_interactions].success);
    assert_eq!(
        FixedBytes::<4>::abi_decode(&response.returnData[num_pre_interactions].returnData, true)?,
        IERC1271::isValidSignatureCall::SELECTOR,
        "Signature was not valid"
    );

    // Check that all post interactions were successful
    response.returnData[num_pre_interactions + 1..]
        .iter()
        .for_each(|r| {
            assert!(r.success, "Post interaction Call failed");
        });

    // Check the status of the commitment, depending on if legacy or not.
    let length = num_pre_interactions + num_post_interactions + 1;

    assert_eq!(
        response.returnData.len(),
        length + 1,
        "Missing expected commitment check"
    );
    assert!(
        response.returnData[length].success,
        "Commitment check failed"
    );
    match legacy {
        true => {
            assert_eq!(
                **response.returnData[length].returnData,
                FixedBytes::<32>::default(),
                "Commitment was not reset (legacy)"
            );
        }
        false => {
            assert_eq!(
                **response.returnData[length].returnData, signing_message,
                "Commitment should NOT have been reset (transient)"
            );
        }
    }

    println!("\nGenerated order was able to be settled successfully!");

    Ok(())
}

/// Maps the interactions to the Multicall3::Call type, verifying that the value is 0
fn map_interactions(interactions: Vec<Interaction>) -> Result<Vec<IMulticall3::Call>> {
    interactions
        .iter()
        .map(|interaction| {
            if !interaction.value.is_zero() {
                return Err(eyre::eyre!("Value must be 0"));
            }

            Ok(IMulticall3::Call {
                target: interaction.target,
                callData: interaction.callData.clone(),
            })
        })
        .collect()
}
