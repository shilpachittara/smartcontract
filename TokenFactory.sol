// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DynamicToken.sol";

contract TokenFactory {
    mapping(address => address[]) private creatorDeployedTokens;

    event TokenPurchase(
        address indexed token,
        address indexed buyer,
        uint256 amount,
        uint256 value
    );
    event TokenSale(
        address indexed token,
        address indexed seller,
        uint256 amount,
        uint256 value
    );
    event LiquidityInitialized(
        address indexed token,
        address indexed pool,
        uint256 reserveBalance,
        uint256 stableBalance
    );
    event TokenCreated(address indexed creator, address indexed token);

    modifier onlyAuthorizedToken() {
        require(
            creatorDeployedTokens[msg.sender].length > 0,
            "Unauthorized caller: Not a registered token"
        );
        _;
    }

    function deployNewToken(
        string memory name,
        string memory symbol
    ) external returns (address) {
        address newToken = address(
            new DynamicToken{
                salt: bytes32(creatorDeployedTokens[msg.sender].length)
            }(name, symbol, address(this))
        );
        creatorDeployedTokens[msg.sender].push(newToken);

        emit TokenCreated(msg.sender, newToken);

        return newToken;
    }

    function predictDeploymentAddress(
        bytes memory bytecode,
        uint256 salt
    ) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    function generateBytecode(
        string memory name,
        string memory symbol
    ) external view returns (bytes memory) {
        bytes memory bytecode = type(DynamicToken).creationCode;

        return abi.encodePacked(bytecode, abi.encode(name, symbol, address(this)));
    }

    function getTokenCount(address creator) external view returns (uint256) {
        return creatorDeployedTokens[creator].length;
    }

    function getDeployedTokens(address creator) external view returns (address[] memory) {
        return creatorDeployedTokens[creator];
    }

    function recordPurchase(uint256 amount, uint256 value) external onlyAuthorizedToken {
        emit TokenPurchase(msg.sender, tx.origin, amount, value);
    }

    function recordSale(uint256 amount, uint256 value) external onlyAuthorizedToken {
        emit TokenSale(msg.sender, tx.origin, amount, value);
    }

    function recordLiquidityInitialization(
        address pool,
        uint256 reserveBalance,
        uint256 stableBalance
    ) external onlyAuthorizedToken {
        emit LiquidityInitialized(msg.sender, pool, reserveBalance, stableBalance);
    }
}