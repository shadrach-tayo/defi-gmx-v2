// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {IReader} from "../interfaces/IReader.sol";
import {Order} from "../types/Order.sol";
import {Position} from "../types/Position.sol";
import {Market} from "../types/Market.sol";
import {MarketUtils} from "../types/MarketUtils.sol";
import {Price} from "../types/Price.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract Long {
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

    // Task 2 - Create an order to long ETH with WETH collateral
    function createLongOrder(uint256 leverage, uint256 wethAmount)
        external
        payable
        returns (bytes32 key)
    {
        uint256 executionFee = 0.1 * 1e18;
        weth.transferFrom(msg.sender, address(this), wethAmount);

        // Task 2.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT,executionFee);

        // Task 2.2 - Send WETH to the order vault
        weth.approve(ROUTER, wethAmount);
        exchangeRouter.sendTokens(WETH, ORDER_VAULT, wethAmount);

        // get current price of ETH in USD from oracle
        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD); // has 8 decimals
        uint256 sizeDeltaUsd = leverage * wethAmount * ethPrice * 1e4;

        // Task 2.3 - Create an order
        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: WETH,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: wethAmount,
                triggerPrice: 0,
                acceptablePrice: ethPrice * (101 / 100), // 1% above the current price of eth
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

        key = exchangeRouter.createOrder(params);

        return key;
    }

    // Task 3 - Get position key
    function getPositionKey() public view returns (bytes32 key) {
        return Position.getPositionKey(
            address(this),
            GM_TOKEN_ETH_WETH_USDC,
            WETH,
            true
        );
    }

    // Task 4 - Get position
    function getPosition(bytes32 key)
        public
        view
        returns (Position.Props memory)
    {
        return reader.getPosition(key);
    }

    // Task 5 - Get position profit and loss
    function getPositionPnlUsd(bytes32 key, uint256 ethPrice)
        external
        view
        returns (int256)
    {
        Position.Props memory position = getPosition(key);

        (int256 positionPnlUsd, int256 uncappedPositionPnlUsd, uint256 sizeDeltaInTokens) = reader.getPositionPnlUsd(
            dataStore,
            Market.Props({
                marketToken: GM_TOKEN_ETH_WETH_USDC,
                indexToken: WETH,
                longToken: WETH,
                shortToken: USDC
            }),
            MarketUtils.MarketPrices({
                indexTokenPrice: Price.Props({
                    min: ethPrice * (99 / 100) * 1e22,
                    max: ethPrice * (101 / 100) * 1e22
                }),
                longTokenPrice: Price.Props({
                    min: ethPrice * (99 / 100)* 1e22,
                    max: ethPrice * (101 / 100) * 1e22
                }),
                shortTokenPrice: Price.Props({
                    min: 1 * 1e30 / 1e6 * 0.99,
                    max: 1 * 1e30 / 1e6 * 1.01
                })
            }),
            key,
            sizeDeltaUsd: position.numbers.sizeDeltaUsd
        );

        return positionPnlUsd;
    }

    // Task 6 - Create an order to close the long position created by this contract
    function createCloseOrder() external payable returns (bytes32 key) {
        uint256 executionFee = 0.1 * 1e18;

        // Task 6.1 - Get position
        Position.Props memory position = getPosition(key);

        // Task 6.2 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        // Task 6.3 - Create an order
        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: WETH,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: position.numbers.sizeDeltaUsd,
                initialCollateralDeltaAmount: position.numbers.initialCollateralDeltaAmount,
                triggerPrice: 0,
                acceptablePrice: ethPrice * (99 / 100) * 1e12, // 1% below the current price of eth
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

        key = exchangeRouter.createOrder(params);

        return key;
    }
}
