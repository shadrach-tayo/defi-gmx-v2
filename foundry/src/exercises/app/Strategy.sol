// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {Math} from "../../lib/Math.sol";
import {Auth} from "../../lib/app/Auth.sol";
import "../../Constants.sol";
import {GmxHelper} from "./GmxHelper.sol";

contract Strategy is Auth, GmxHelper {
    IERC20 public constant weth = IERC20(WETH);
    GmxHelper public gmxHelper;

    constructor(address oracle)
        GmxHelper(
            GM_TOKEN_ETH_WETH_USDC,
            WETH,
            USDC,
            CHAINLINK_ETH_USD,
            CHAINLINK_USDC_USD,
            oracle
        )
    {}

    receive() external payable {}

    // Task 1: Calculate total vaule managed by this contract in terms of WETH
    function totalValueInToken() external view returns (uint256) {
        uint256 value = weth.balanceOf(address(this));
        uint256 remainingCollateral = getPositionWithPnlInToken();
        if (remainingCollateral >= 0) {
            value += uint256(remainingCollateral);
        } else {
            value -= Math.min(value, uint256(-remainingCollateral));
        }
        return value;
    }

    // Task 2: Create market increase order
    function increase(uint256 wethAmount)
        external
        payable
        auth
        returns (bytes32 orderKey)
    {
        orderKeycreateIncreaseShortPositionOrder(msg.value, wethAmount);
    }

    // Task 3: Create market decrease order
    // Function call is from the vault when the callback contract is not address(0).
    function decrease(uint256 wethAmount, address callbackContract)
        external
        payable
        auth
        returns (bytes32 orderKey)
    {
        if (callbackContract == address(0)) {
            return createDecreaseShortPositionOrder(
                msg.value, wethAmount, address(this), callbackContract, 0
            );
        } else {
            uint256 maxCallbackGasLimit = getMaxCallbackGasLimit();
            require(
                msg.value > maxCallbackGasLimit,
                "msg.value < maxCallbackGasLimit"
            );

            Position.Props memory position = getPosition(getPositionKey());
            uint256 longTokenAmount = getPositionCollateralAmount() * wethAmount
                / getPositionWithPnlInToken();
            orderKey = createDecreaseShortPositionOrder(
                msg.value,
                longTokenAmount,
                callbackContract,
                callbackContract,
                maxCallbackGasLimit
            );
        }
    }

    // Task 4: Cancel an order
    function cancel(bytes32 orderKey) external payable auth {
        cancelOrder(orderKey);
    }

    // Task 5: Claim funding fees
    function claim() external {
        claimFundingFees();
    }

    function transfer(address dst, uint256 amount) external auth {
        weth.transfer(dst, amount);
    }

    function withdraw(address token) external auth {
        if (token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "Send ETH failed");
        } else {
            IERC20(token).transfer(
                msg.sender, IERC20(token).balanceOf(address(this))
            );
        }
    }
}
