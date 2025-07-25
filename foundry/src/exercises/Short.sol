// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {IReader} from "../interfaces/IReader.sol";
import {Order} from "../types/Order.sol";
import {Position} from "../types/Position.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract Short {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant usdc = IERC20(USDC);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    IDataStore constant dataStore = IDataStore(DATA_STORE);
    IReader constant reader = IReader(READER);
    Oracle immutable oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    // Task 1 - Receive execution fee refund from GMX
    receive() external payable {}

    // Task 2 - Create an order to short ETH with USDC collateral
    function createShortOrder(uint256 leverage, uint256 usdcAmount)
        external
        payable
        returns (bytes32 key)
    {
        uint256 executionFee = 0.1 * 1e18;
        usdc.transferFrom(msg.sender, address(this), usdcAmount);

        // Task 2.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}({
            receiver: ORDER_VAULT,
            amount: executionFee
        });

        // Task 2.2 - Send USDC to the order vault
        usdc.approve(EXCHANGE_ROUTER, usdcAmount);
        exchangeRouter.sendTokens(address(usdc), ORDER_VAULT, usdcAmount);

        uint256 usdcPrice = oracle.getPrice(CHAINLINK_USDC_USD);
        uint256 sizeDeltaUsd = leverage * usdcAmount * usdcPrice * 1e16;

        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        uint256 acceptablePrice = ethPrice * 1e4 * (90 / 100);

        // Task 2.3 - Create an order to short ETH with USDC collateral
        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: USDC,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: ethPrice * 1e4 * (99 / 100), // 1% above the current price of eth
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: false,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }

    // Task 3 - Get position key
    function getPositionKey() public view returns (bytes32 key) {
        return Position.getPositionKey(
            address(this), GM_TOKEN_ETH_WETH_USDC, USDC, false
        );
    }

    // Task 4 - Get position
    function getPosition(bytes32 key)
        public
        view
        returns (Position.Props memory)
    {
        return reader.getPosition(address(dataStore), key);
    }

    // Task 5 - Create an order to close the short position created by this contract
    function createCloseOrder() external payable returns (bytes32 key) {
        uint256 executionFee = 0.1 * 1e18;

        // Task 5.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}({
            receiver: ORDER_VAULT,
            amount: executionFee
        });

        // Task 5.2 - Create an order to close the short position
        Position.Props memory position = getPosition(key);
        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        address market = position.market;
        uint256 acceptablePrice = ethPrice * 1e4 * (110 / 100);

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: USDC,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: position.numbers.sizeInUsd,
                initialCollateralDeltaAmount: position.numbers.collateralAmount,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }
}
