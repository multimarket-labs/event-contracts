// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IERC721Permit
 * @notice ERC721 with permit extension for gasless approvals
 * @dev Extends OpenZeppelin's IERC721 with EIP-2612 style permit functionality
 */
interface IERC721Permit is IERC721 {
    /**
     * @notice Returns the domain separator used in the encoding of the signature for permit
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Approve of a specific token ID for spending by spender via signature
     * @param spender The account that is being approved
     * @param tokenId The ID of the token that is being approved for spending
     * @param deadline The deadline timestamp by which the call must be mined for the approve to work
     * @param v Must produce valid secp256k1 signature from the holder along with `r` and `s`
     * @param r Must produce valid secp256k1 signature from the holder along with `v` and `s`
     * @param s Must produce valid secp256k1 signature from the holder along with `r` and `v`
     */
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
