// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/sailfish/IFactory.sol";
import {IVault} from "./interfaces/sailfish/IVault.sol";
import "./TokenFactory.sol";

contract DynamicToken is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public authorizedTraders;

    uint256 public liquidityThreshold = 10.05 ether; // Trigger for deploying liquidity
    uint256 public reserveTokenBalance; // Current balance of tokens in reserve
    uint256 public virtualStableBalance = 10 ether; // Initial stablecoin virtual balance
    uint256 private constant SCALE = 1 ether;

    uint256 private constantPrecision;

    address public factoryManager;
    address public stablePoolFactory;
    address public vaultAddress;

    bool public isLiquidityDeployed = false;
    uint256 public circulatingTokenSupply = 0;

    string public constant TOKEN_TYPE = "DynamicToken";

    constructor(
        string memory _name,
        string memory _symbol,
        address _factoryManager
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        reserveTokenBalance = 1_000_000_000 * SCALE;
        _mint(address(this), reserveTokenBalance);

        unchecked {
            constantPrecision = reserveTokenBalance * virtualStableBalance;
        }

        factoryManager = _factoryManager;
    }

    function purchaseTokens() external payable {
        require(msg.value > 0, "Invalid payment amount");
        require(!isLiquidityDeployed, "Liquidity already deployed");

        uint256 tokensToIssue = calculateTokenOutput(msg.value);

        unchecked {
            virtualStableBalance += msg.value;
            reserveTokenBalance -= tokensToIssue;
        }

        if (virtualStableBalance >= liquidityThreshold) {
            deployLiquidity();
        }

        TokenFactory(factoryManager).recordPurchase(tokensToIssue, msg.value);

        _transfer(address(this), msg.sender, tokensToIssue);
        circulatingTokenSupply += tokensToIssue;
    }

    function sellTokens(uint256 amount) external {
        require(amount > 0, "Invalid token amount");
        require(!isLiquidityDeployed, "Liquidity already deployed");

        uint256 stableAmount = calculateStableOutput(amount);

        unchecked {
            reserveTokenBalance += amount;
            virtualStableBalance -= stableAmount;
        }

        IERC20(address(this)).transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(stableAmount);

        circulatingTokenSupply -= amount;

        TokenFactory(factoryManager).recordSale(amount, stableAmount);
    }

    function deployLiquidity() internal {
        address pair = IFactory(stablePoolFactory).deploy(
            NATIVE_TOKEN,
            toToken(IERC20(address(this)))
        );

        _approve(address(this), vaultAddress, type(uint256).max);

        uint256 deployableBalance = virtualStableBalance - 10 ether; // Remove initial virtual balance
        IVault(vaultAddress).addLiquidity{value: deployableBalance}(
            address(this),
            address(0),
            false,
            deployableBalance,
            deployableBalance,
            0,
            0,
            address(this),
            type(uint256).max
        );

        TokenFactory(factoryManager).recordLiquidityInitialization(pair, reserveTokenBalance, virtualStableBalance);
        isLiquidityDeployed = true;
    }

    function calculateTokenOutput(uint256 stableAmount) public view returns (uint256) {
        uint256 newPricePoint = constantPrecision / (virtualStableBalance + stableAmount);
        return reserveTokenBalance - newPricePoint;
    }

    function calculateStableOutput(uint256 tokenAmount) public view returns (uint256) {
        uint256 newPricePoint = constantPrecision / (reserveTokenBalance + tokenAmount);
        return virtualStableBalance - newPricePoint;
    }
}