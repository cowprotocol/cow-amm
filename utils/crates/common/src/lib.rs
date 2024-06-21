mod contracts;

use alloy::transports::http::reqwest::Url;
pub use contracts::ComposableCoW;
pub use contracts::ConstantProductHelper;
pub use contracts::GPv2Settlement;
pub use contracts::IConstantProductHelper;
pub use contracts::IMulticall3;
pub use contracts::IPriceOracle;
pub use contracts::LegacyTradingParams;
pub use contracts::Order;
pub use contracts::IERC1271;

pub fn rpc_url() -> Url {
    match std::env::var("RPC_URL") {
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
    }
}
