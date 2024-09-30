// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Script.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/lendingcontract.sol";

contract SetupScript is Script {

    uint32 ARBEID = 40231;
    uint32 ETHEID = 40161;
    uint32 OPTEID = 40232;
    uint32 BASEID = 40245;
    uint32 BEREID = 40291;

    address nftContractAddress = 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030;
    address opsCotnractAddress = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;

    address deposit_ARB_Address = 0x6D08b0aa7eeCb491c61190418df9235d1b53fcD8;
    address deposit_ETH_Address = 0x0cFbC9aaEF1fbCA9bbeF916aD4dABf0d6103451b;
    address deposit_OPT_Address = 0x6D08b0aa7eeCb491c61190418df9235d1b53fcD8;
    address deposit_BAS_Address = 0x85a5A8AfF78df7097907952A366C6F86F3d4Aa10;
    
    address payable lending_ARB_Address = payable(0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B);
    address payable lending_ETH_Address = payable(0xE0649C73277Fb736455Ec3DFa6A446a2a864f831);
    address payable lending_OPT_Address = payable(0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030);
    address payable lending_BAS_Address = payable(0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183);
    address payable lending_BER_Address = payable(0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183);

    address weth_ARB_Address = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address weth_ETH_Address = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0;
    address weth_OPT_Address = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3;
    address weth_BAS_Address = 0x4200000000000000000000000000000000000006;
    address weth_BER_Address = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8; // Actually WBERA on Bera

    address wsteth_ARB_Address = 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6;
    address wsteth_ETH_Address = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;
    address wsteth_OPT_Address = 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59;
    address wsteth_BAS_Address = 0x14440344256002a5afaA1403EbdAf4bf9a5499E3;
    address wsteth_BER_Address = 0x6E1E9896e93F7A71ECB33d4386b49DeeD67a231A; // ACtually WETH on Bera
    
    function run() external {
        vm.startBroadcast();
        address issuer = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
        CrossChainLendingContract lendingBER = new CrossChainLendingContract(issuer, weth_BER_Address, uint256(BEREID));
        AdminDepositContract depositBER = new AdminDepositContract(address(0), address(lendingBER), address(weth_BER_Address), address(wsteth_BER_Address), 40231, BEREID, 0x6EDCE65403992e310A62460808c4b910D972f10f, issuer, issuer);
        console.log(address(lendingBER));
        console.log(address(depositBER));
        depositBER.addSupportedToken(wsteth_BER_Address);
        depositBER.addSupportedToken(weth_BER_Address);

        // lendingBER.poolDeposit{value: 0.01*1e18}(0.01*1e18);

        depositBER.setPeer(ARBEID, addressToBytes32(opsCotnractAddress));
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
