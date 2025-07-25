// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {Order} from "../types/Order.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract TakeProfitAndStopLoss {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant usdc = IERC20(USDC);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    Oracle immutable oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    // Task 1 - Receive execution fee refund from GMX
    receive() external payable {}

    // Task 2 - Create orders to
    // 1. Long ETH with USDC collateral
    // 2. Stop loss for ETH price below 90% of current price
    // 3. Take profit for ETH price above 110% of current price
    function createTakeProfitAndStopLossOrders(
        uint256 leverage,
        uint256 usdcAmount
    ) external payable returns (bytes32[] memory keys) {
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

       
        

        // Task 2.3 - Create a long order to long ETH with USDC collateral
        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        uint256 usdcPrice = oracle.getPrice(CHAINLINK_USDC_USD);
        uint256 sizeDeltaUsd = leverage * usdcAmount * usdcPrice * 1e16;

        uint256 acceptablePrice = ethPrice * 1e4 * (101 / 100);
       
       IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils.CreateOrderParams({
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
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        bytes32 longOrderKey = exchangeRouter.createOrder(params);

        // Task 2.4 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}({
            receiver: ORDER_VAULT,
            amount: executionFee
        });

        // Task 2.5 - Create a stop loss for 90% of current ETH price
         IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils.CreateOrderParams({
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
                triggerPrice: ethPrice * 1e4 * (90 / 100),
                acceptablePrice: 0,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: block.timestamp
            }),
            orderType: Order.OrderType.StopLossDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        bytes32 stopLoossOrderKey = exchangeRouter.createOrder(params);

        // Task 2.6 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}({
            receiver: ORDER_VAULT,
            amount: executionFee
        });

        // Task 2.7 - Create an order to take profit above 110% of current price
        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils.CreateOrderParams({
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
                triggerPrice: ethPrice * 1e4 * (110 / 100),
                acceptablePrice: ethPrice * 1e4 * (99 / 100),
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.LimitDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        bytes32 takeProfitOrderKey = exchangeRouter.createOrder(params);

        return new bytes32[](3) {
            longOrderKey,
            stopLoossOrderKey,
            takeProfitOrderKey
        };
    }
}
