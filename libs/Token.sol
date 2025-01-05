// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// UniversalTokenLib: A library to manage ERC20, ERC1155, and ERC721 tokens seamlessly.

bytes32 constant ADDR_MASK = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
bytes32 constant TOKEN_ID_MASK = 0x00FFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000;
uint256 constant TOKEN_ID_SHIFT = 160;
bytes32 constant SPEC_MASK = 0xFF00000000000000000000000000000000000000000000000000000000000000;

string constant DEFAULT_NATIVE_SYMBOL = "EDU";
address constant WRAPPED_NATIVE_ADDRESS = 0xbe52762D8D68d183C7Cf4BB3e2aaa312e47C7084;

type UniversalToken is bytes32;
type TokenType is bytes32;

using {TokenType_equals as ==} for TokenType global;
using {UniversalToken_equals as ==} for UniversalToken global;
using {UniversalToken_lt as <} for UniversalToken global;
using {UniversalToken_lte as <=} for UniversalToken global;
using {UniversalToken_notEqual as !=} for UniversalToken global;

UniversalToken constant NATIVE =
    UniversalToken.wrap(bytes32(0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE) & ADDR_MASK);

function TokenType_equals(TokenType a, TokenType b) pure returns (bool) {
    return TokenType.unwrap(a) == TokenType.unwrap(b);
}

function UniversalToken_equals(UniversalToken a, UniversalToken b) pure returns (bool) {
    return UniversalToken.unwrap(a) == UniversalToken.unwrap(b);
}

function UniversalToken_notEqual(UniversalToken a, UniversalToken b) pure returns (bool) {
    return UniversalToken.unwrap(a) != UniversalToken.unwrap(b);
}

function UniversalToken_lt(UniversalToken a, UniversalToken b) pure returns (bool) {
    return UniversalToken.unwrap(a) < UniversalToken.unwrap(b);
}

function UniversalToken_lte(UniversalToken a, UniversalToken b) pure returns (bool) {
    return UniversalToken.unwrap(a) <= UniversalToken.unwrap(b);
}

library TokenTypeLib {
    TokenType constant ERC20 =
        TokenType.wrap(0x0000000000000000000000000000000000000000000000000000000000000000);

    TokenType constant ERC721 =
        TokenType.wrap(0x0100000000000000000000000000000000000000000000000000000000000000);

    TokenType constant ERC1155 =
        TokenType.wrap(0x0200000000000000000000000000000000000000000000000000000000000000);
}

function createUniversalToken(IERC20 token) pure returns (UniversalToken) {
    return UniversalToken.wrap(bytes32(uint256(uint160(address(token)))));
}

function createUniversalToken(TokenType type_, uint88 id_, address addr_) pure returns (UniversalToken) {
    return UniversalToken.wrap(
        TokenType.unwrap(type_) | 
        (bytes32(uint256(id_)) << TOKEN_ID_SHIFT) & TOKEN_ID_MASK |
        bytes32(uint256(uint160(addr_)))
    );
}

library UniversalTokenLib {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    function extractAddress(UniversalToken token) internal pure returns (address) {
        return address(uint160(uint256(UniversalToken.unwrap(token) & ADDR_MASK)));
    }

    function extractID(UniversalToken token) internal pure returns (uint256) {
        return uint256((UniversalToken.unwrap(token) & TOKEN_ID_MASK) >> TOKEN_ID_SHIFT);
    }

    function extractType(UniversalToken token) internal pure returns (TokenType) {
        return TokenType.wrap(UniversalToken.unwrap(token) & SPEC_MASK);
    }

    function asERC20(UniversalToken token) internal pure returns (IERC20Metadata) {
        return IERC20Metadata(extractAddress(token));
    }

    function asERC1155(UniversalToken token) internal pure returns (IERC1155) {
        return IERC1155(extractAddress(token));
    }

    function asERC721(UniversalToken token) internal pure returns (IERC721Metadata) {
        return IERC721Metadata(extractAddress(token));
    }

    function balance(UniversalToken token, address account) internal view returns (uint256) {
        if (token == NATIVE) {
            return account.balance;
        } else if (extractType(token) == TokenTypeLib.ERC20) {
            require(extractID(token) == 0, "Invalid ERC20 ID");
            return asERC20(token).balanceOf(account);
        } else if (extractType(token) == TokenTypeLib.ERC1155) {
            return asERC1155(token).balanceOf(account, extractID(token));
        } else if (extractType(token) == TokenTypeLib.ERC721) {
            return asERC721(token).ownerOf(extractID(token)) == account ? 1 : 0;
        }

        revert("Unsupported token type");
    }

    function totalSupply(UniversalToken token) internal view returns (uint256) {
        if (token == NATIVE) {
            revert("Native tokens do not have total supply");
        } else if (extractType(token) == TokenTypeLib.ERC20) {
            return asERC20(token).totalSupply();
        } else if (extractType(token) == TokenTypeLib.ERC1155) {
            return ERC1155Supply(extractAddress(token)).totalSupply(extractID(token));
        } else if (extractType(token) == TokenTypeLib.ERC721) {
            return 1;
        }

        revert("Unsupported token type");
    }

    function transferFrom(
        UniversalToken token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (token == NATIVE) {
            require(sender == address(this), "Native token transfer not supported");
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Native token transfer failed");
        } else if (extractType(token) == TokenTypeLib.ERC20) {
            if (sender == address(this)) {
                asERC20(token).safeTransfer(recipient, amount);
            } else {
                asERC20(token).safeTransferFrom(sender, recipient, amount);
            }
        } else if (extractType(token) == TokenTypeLib.ERC721) {
            require(amount == 1, "Invalid ERC721 transfer amount");
            asERC721(token).safeTransferFrom(sender, recipient, extractID(token));
        } else if (extractType(token) == TokenTypeLib.ERC1155) {
            asERC1155(token).safeTransferFrom(sender, recipient, extractID(token), amount, "");
        } else {
            revert("Unsupported token type");
        }
    }
}