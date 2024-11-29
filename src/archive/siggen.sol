// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SignatureGenerator {
    function getMessageHash(
        address _withdrawer,
        uint256 token,
        uint256 nftId,
        uint256 amount,
        uint256 targetChainId,
        uint256 timestamp,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_withdrawer, token, nftId, amount, targetChainId, timestamp, nonce));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) public pure returns (address) {
        require(_signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }
}
