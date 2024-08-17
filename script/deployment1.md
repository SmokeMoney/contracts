# ARBITRUM SEPOLIA
# NFT CONTRACT DEPLOYMENT
## ARGUMENTS string memory name, string memory symbol, address _issuer, address _owner, uint256 _mintPrice, uint256 _maxNFTs
forge create src/corenft.sol:CoreNFTContract --constructor-args "AutoGas", "OG" 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 20000000000000000 10 --rpc-url arbitrum_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030
Transaction hash: 0x9ad5ecf8fc66bf4caaebbbba8d81d3d29246edef7ac3d5ab68053ef233c61ab7

# OPERATIONS CONTRACT DEPLOYMENT
## ARGUMENTS address _coreNFTContract, address _endpoint, address _pythContract, address _issuer, address _owner, uint32 _adminChainId
forge create src/accountops.sol:OperationsContract --constructor-args 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030 0x6EDCE65403992e310A62460808c4b910D972f10f 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 40231 --rpc-url arbitrum_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819
Transaction hash: 0x5697f38cc76f0b1437f83fdc00ad15168c61aae29ae209860411eada99db48b4

# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73 40231 --rpc-url arbitrum_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B
Transaction hash: 0x1d4e1672c8d83f16bfa4df1c5084a896e12b57a0339c6246d5dc53eb9f9f890b

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6 40231 40231 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url arbitrum_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x6D08b0aa7eeCb491c61190418df9235d1b53fcD8
Transaction hash: 0x5d2d4116c67c853e637df45519abed1725500c3d07816b4b6de3dfeeca698cc3


# MAINNET
# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0xf531B8F309Be94191af87605CfBf600D71C2cFe0 40161 --rpc-url mainnet_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0xE0649C73277Fb736455Ec3DFa6A446a2a864f831
Transaction hash: 0xe1bbfea53d49e0c101f793513f4c86ddb6924f35ca06bbe1b5e62f27927de969

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x0000000000000000000000000000000000000000 0xE0649C73277Fb736455Ec3DFa6A446a2a864f831 0xf531B8F309Be94191af87605CfBf600D71C2cFe0 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819 40231 40161 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url mainnet_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x0cFbC9aaEF1fbCA9bbeF916aD4dABf0d6103451b
Transaction hash: 0xa6124dcb88b7d5bf140c5238c2235ea82fd2ee843165d9cf15e9358596a7ff8b


# OPTIMISM
# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3 40232 --rpc-url optimism_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030
Transaction hash: 0xbe3fab9661227d7285c9d8ce8cb12d496251565aecbf2c30c380d3b827b515ff

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x0000000000000000000000000000000000000000 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59 40231 40232 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url optimism_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x6D08b0aa7eeCb491c61190418df9235d1b53fcD8
Transaction hash: 0x8ae677a03f200cafb5507e82a13900e9257043a15265e31d08429ce54e332889


# BASE
# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x4200000000000000000000000000000000000006 40245 --rpc-url base_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183
Transaction hash: 0xf21faf72f78b48c1e785c73e0621b28ac0adcdb524d9022a95d9d91cc8ca7ac3

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x0000000000000000000000000000000000000000 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183 0x4200000000000000000000000000000000000006 0x14440344256002a5afaA1403EbdAf4bf9a5499E3 40231 40245 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url base_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x85a5A8AfF78df7097907952A366C6F86F3d4Aa10
Transaction hash: 0x472194173049c45d370387dc251888301806dd57ff925cef8b190103598c6745

    
cast send --rpc-url mainnet_sepolia <contractAddress>  "mintTo(address)" <arg> --private-key=$PRIVATE_KEY

forge script script/ArbitrumSetup.s.sol:SetupScript --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

    curl -X 'GET' \
    'https://hermes.pyth.network/v2/updates/price/latest?ids%5B%5D=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace&ids%5B%5D=0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784'


forge inspect src/lendingcontract.sol:CrossChainLendingContract abi > ../vite-react/src/abi/CrossChainLendingContract.abi.json
forge inspect src/corenft.sol:CoreNFTContract abi > ../vite-react/src/abi/CoreNFTContract.abi.json
forge inspect src/deposit.sol:AdminDepositContract abi > ../vite-react/src/abi/AdminDepositContract.abi.json
forge inspect src/accountops.sol:OperationsContract abi > ../vite-react/src/abi/OperationsContract.abi.json

forge inspect src/lendingcontract.sol:CrossChainLendingContract abi > ../cross-chain-lending-backend/src/abi/CrossChainLendingContract.abi.json
forge inspect src/corenft.sol:CoreNFTContract abi > ../cross-chain-lending-backend/src/abi/CoreNFTContract.abi.json
forge inspect src/deposit.sol:AdminDepositContract abi > ../cross-chain-lending-backend/src/abi/AdminDepositContract.abi.json
forge inspect src/accountops.sol:OperationsContract abi > ../cross-chain-lending-backend/src/abi/OperationsContract.abi.json
forge inspect lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:ERC20 abi > ../cross-chain-lending-backend/src/abi/ERC20.abi.json


# VERIFY CONTRACTS
╰─λ cast abi-encode "constructor(address,address,uint256)" 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0xf531B8F309Be94191af87605CfBf600D71C2cFe0 40161
╰─λ forge verify-contract --chain-id 11155111 0xE0649C73277Fb736455Ec3DFa6A446a2a864f831 src/lendingcontract.sol:CrossChainLendingContract --watch --constructor-args 0x00000000000000000000000003773f85756acac65a869e89e3b7b2fcda6be140000000000000000000000000f531b8f309be94191af87605cfbf600d71c2cfe00000000000000000000000000000000000000000000000000000000000009ce1