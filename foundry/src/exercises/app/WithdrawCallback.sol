// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IWeth} from "../../interfaces/IWeth.sol";
import {Order} from "../../types/Order.sol";
import {EventUtils} from "../../types/EventUtils.sol";
import {Math} from "../../lib/Math.sol";
import {IStrategy} from "../../lib/app/IStrategy.sol";
import {IVault} from "../../lib/app/IVault.sol";
import {Auth} from "../../lib/app/Auth.sol";
import "../../Constants.sol";

contract WithdrawCallback is Auth {
    IWeth public constant weth = IWeth(WETH);
    IVault public immutable vault;

    mapping(bytes32 => address) public refunds;

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    modifier onlyGmx() {
        require(msg.sender == ORDER_HANDLER, "not authorized");
        _;
    }

    function setRefundAccount(bytes32 key, address account) private {
        require(refunds[key] == address(0), "refund account already set");
        refunds[key] = account;
    }

    // Task 1: Refund execution fee callback
    function refundExecutionFee(
        // Order key
        bytes32 key,
        EventUtils.EventLogData memory eventData
    ) external payable onlyGmx {
        if (refunds[key] != address(0)) {
            address refundAccount = refunds[key];
            delete refunds[key];

            (bool ok,) = refundAccount.call{value: msg.value}("");
            require(ok, "refund failed");
        }
    }

    // Task 2: Order execution callback
    function afterOrderExecution(
        // Order key
        bytes32 key,
        Order.Props memory order,
        EventUtils.EventLogData memory eventData
    ) external onlyGmx {
        require(
            order.orderType == Order.OrderType.MARKET_INCREASE,
            "order type is not market increase"
        );
        IVault.WithdrawOrder memory withdrawOrder = vault.getWithdrawOrder(key);
        require(withdrawOrder.account != address(0), "invalid order key");

        // Set refund account
        setRefundAccount(key, withdrawOrder.account);

        // Remove withdraw order
        vault.removeWithdrawOrder(key, true);

        // Transfer at most the amount of WETH stored in the withdraw order to the account
        //that is associated with this withdraw order. Send remaining WETH to the vault.
        uint256 bal = weth.balanceOf(address(this));
        if (withdrawOrder.weth > bal) {
            weth.transfer(withdrawOrder.account, bal);
        } else {
            weth.transfer(withdrawOrder.account, withdrawOrder.weth);
            weth.transfer(address(vault), bal - withdrawOrder.weth);
        }
    }

    // Task 3: Order cancellation callback
    function afterOrderCancellation(
        // Order key
        bytes32 key,
        Order.Props memory order,
        EventUtils.EventLogData memory eventData
    ) external onlyGmx {
        IVault.WithdrawOrder memory withdrawOrder = vault.getWithdrawOrder(key);
        require(
            order.orderType == Order.OrderType.MARKET_DECREASE,
            "invalid order type"
        );
        require(withdrawOrder.account != address(0), "invalid order key");

        // Set refund account
        setRefundAccount(key, withdrawOrder.account);

        // Remove withdraw order
        vault.removeWithdrawOrder(key, false);
    }

    // Task 4: Order frozen callback
    function afterOrderFrozen(
        // Order key
        bytes32 key,
        Order.Props memory order,
        EventUtils.EventLogData memory eventData
    ) external onlyGmx {
        IVault.WithdrawOrder memory withdrawOrder = vault.getWithdrawOrder(key);
        require(
            order.orderType == Order.OrderType.MARKET_DECREASE,
            "invalid order type"
        );
        require(withdrawOrder.account != address(0), "invalid order key");

        // Set refund account
        setRefundAccount(key, withdrawOrder.account);

        // Remove withdraw order
        vault.removeWithdrawOrder(key, false);
    }

    function transfer(address dst, uint256 amount) external auth {
        weth.transfer(dst, amount);
    }
}
