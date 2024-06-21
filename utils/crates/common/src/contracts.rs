use alloy::{
    primitives::{b256, keccak256, FixedBytes},
    sol,
};
use IConstantProductHelper::OnchainOrder;

// Codegen from ABI file to interact with the contract.
sol!(
    #[allow(missing_docs)]
    #[allow(clippy::too_many_arguments)]
    #[derive(Debug)]
    #[sol(rpc)]
    ComposableCoW,
    "../../../out/ComposableCoW.sol/ComposableCoW.json"
);

sol!(
    #[allow(missing_docs)]
    #[allow(clippy::too_many_arguments)]
    #[derive(Debug)]
    #[sol(rpc)]
    GPv2Settlement,
    "../../../out/GPv2Settlement.sol/GPv2Settlement.json"
);

sol!(
    #[allow(missing_docs)]
    #[allow(clippy::too_many_arguments)]
    #[derive(Debug)]
    #[sol(rpc)]
    IPriceOracle,
    "../../../out/IPriceOracle.sol/IPriceOracle.json"
);

sol!(
    #[allow(missing_docs)]
    #[allow(clippy::too_many_arguments)]
    #[derive(Debug)]
    #[sol(rpc)]
    ConstantProductHelper,
    "../../../out/ConstantProductHelper.sol/ConstantProductHelper.json"
);

sol! {
    #[allow(missing_docs)]
    #[derive(Debug)]
    interface IMulticall3 {
        struct Call {
            address target;
            bytes callData;
        }

        struct Result {
            bool success;
            bytes returnData;
        }

        function tryAggregate(bool requireSuccess, Call[] calldata calls) public payable returns (Result[] memory returnData);
    }
}

sol! {
    #[allow(missing_docs)]
    #[derive(Debug)]
    interface IERC1271 {
        function isValidSignature(bytes32 _hash, bytes calldata signature) external view returns (bytes4 magicValue);
    }

}

sol! {
    #[allow(missing_docs)]
    #[derive(Debug)]
    /// Legacy trading parameters.
    struct LegacyTradingParams {
        address token0;
        address token1;
        uint256 minTradedToken0;
        address priceOracle;
        bytes priceOracleData;
        bytes32 appData;
    }
}

sol! {
    #[allow(missing_docs)]
    #[derive(Debug)]
    /// GPv2 _real_ order signing struct
    struct Order {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        string kind;
        bool partiallyFillable;
        string sellTokenBalance;
        string buyTokenBalance;
    }
}

sol! {
    #[allow(missing_docs)]

    #[derive(Debug)]
    contract IConstantProductHelper {
        /// GPv2 order data.
        struct OnchainOrder {
            address sellToken;
            address buyToken;
            address receiver;
            uint256 sellAmount;
            uint256 buyAmount;
            uint32 validTo;
            bytes32 appData;
            uint256 feeAmount;
            bytes32 kind;
            bool partiallyFillable;
            bytes32 sellTokenBalance;
            bytes32 buyTokenBalance;
        }

        struct Interaction {
            address target;
            uint256 value;
            bytes callData;
        }
        function d() external view returns (OnchainOrder memory order, Interaction[] memory interactions, bytes memory sig);
    }
}

// Implement a From trait for the OffchainOrder struct to convert it to OrderData
impl From<Order> for IConstantProductHelper::OnchainOrder {
    fn from(order: Order) -> Self {
        Self {
            sellToken: order.sellToken,
            buyToken: order.buyToken,
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            kind: keccak256(order.kind),
            partiallyFillable: order.partiallyFillable,
            sellTokenBalance: keccak256(order.sellTokenBalance),
            buyTokenBalance: keccak256(order.buyTokenBalance),
        }
    }
}

impl TryFrom<OnchainOrder> for Order {
    type Error = eyre::Report;

    fn try_from(order: OnchainOrder) -> Result<Self, Self::Error> {
        const KIND_SELL: FixedBytes<32> =
            b256!("f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775");
        const KIND_BUY: FixedBytes<32> =
            b256!("6ed88e868af0a1983e3886d5f3e95a2fafbd6c3450bc229e27342283dc429ccc");
        const BALANCE_ERC20: FixedBytes<32> =
            b256!("5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9");
        const BALANCE_EXTERNAL: FixedBytes<32> =
            b256!("abee3b73373acd583a130924aad6dc38cfdc44ba0555ba94ce2ff63980ea0632");
        const BALANCE_INTERNAL: FixedBytes<32> =
            b256!("4ac99ace14ee0a5ef932dc609df0943ab7ac16b7583634612f8dc35a4289a6ce");

        Ok(Self {
            sellToken: order.sellToken,
            buyToken: order.buyToken,
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            kind: match order.kind {
                KIND_SELL => "sell".to_string(),
                KIND_BUY => "buy".to_string(),
                _ => return Err(eyre::eyre!("Invalid order kind")),
            },
            partiallyFillable: order.partiallyFillable,
            sellTokenBalance: match order.sellTokenBalance {
                BALANCE_ERC20 => "erc20".to_string(),
                BALANCE_EXTERNAL => "external".to_string(),
                BALANCE_INTERNAL => "internal".to_string(),
                _ => return Err(eyre::eyre!("Invalid sell token balance kind")),
            },
            buyTokenBalance: match order.buyTokenBalance {
                BALANCE_ERC20 => "erc20".to_string(),
                BALANCE_EXTERNAL => "external".to_string(),
                BALANCE_INTERNAL => "internal".to_string(),
                _ => return Err(eyre::eyre!("Invalid buy token balance kind")),
            },
        })
    }
}
