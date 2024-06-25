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
pub use contracts::IERC20;

pub fn rpc_url() -> Url {
    std::env::var("RPC_URL")
        .expect("Environment variable `RPC_URL` is not set")
        .parse()
        .expect("Invalid URL")
}
