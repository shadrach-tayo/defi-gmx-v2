// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Market} from "./Market.sol";
import {MarketPoolValueInfo} from "./MarketPoolValueInfo.sol";

library GlvDepositUtils {
    struct CreateGlvDepositParams {
        address glv;
        address market;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minGlvTokens;
        uint256 executionFee;
        uint256 callbackGasLimit;
        bool shouldUnwrapNativeToken;
        bool isMarketTokenDeposit;
    }

    struct CreateGlvDepositCache {
        uint256 marketTokenAmount;
        uint256 initialLongTokenAmount;
        uint256 initialShortTokenAmount;
    }

    struct ExecuteGlvDepositParams {
        address dataStore;
        address eventEmitter;
        address glvVault;
        address oracle;
        bytes32 key;
        uint256 startingGas;
        address keeper;
    }

    struct ExecuteGlvDepositCache {
        Market.Props market;
        MarketPoolValueInfo.Props marketPoolValueInfo;
        uint256 marketTokenSupply;
        uint256 receivedMarketTokens;
        uint256 mintAmount;
        uint256 marketCount;
        uint256 oraclePriceCount;
        uint256 glvValue;
        uint256 glvSupply;
    }

    struct CancelGlvDepositParams {
        address dataStore;
        address eventEmitter;
        address glvVault;
        bytes32 key;
        address keeper;
        uint256 startingGas;
        string reason;
        bytes reasonBytes;
    }

    address public constant RECEIVER_FOR_FIRST_GLV_DEPOSIT = address(1);
}
