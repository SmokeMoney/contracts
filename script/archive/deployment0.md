# OPTIMISM SEPOLIA
# NFT CONTRACT DEPLOYMENT
## ARGUMENTS string memory name, string memory symbol, address _issuer, address _owner, uint256 _mintPrice, uint256 _maxNFTs
forge create src/corenft.sol:CoreNFTContract --constructor-args "AutoGas", "OG" 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 20000000000000000 10 --rpc-url arbitrum_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183
Transaction hash: 0x3d68ce45699744c2edfc4d8cb14d580aa11e3a75dc2179cedfc4d64c25eb4a59

# OPERATIONS CONTRACT DEPLOYMENT
## ARGUMENTS address _coreNFTContract, address _endpoint, address _pythContract, address _issuer, address _owner, uint32 _adminChainId
forge create src/accountops.sol:OperationsContract --constructor-args 0x2cbe484b1e2fe4ffa28fef0caa0c9e0d724fe183 0x6edce65403992e310a62460808c4b910d972f10f 0x0708325268dF9F66270F1401206434524814508b 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 40232 --rpc-url optimism_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0xF4D2D99b401859c7b825D145Ca76125455154245
Transaction hash: 0x4b519c1f0ab215a7dbf572d719b11c7739cbe7a10c4bf40e0503e01e93fe725f

# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3 40232 --rpc-url optimism_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x74f96Ed7d11e9028352F44345F4A1D35bDF7d0E4
Transaction hash: 0x4e6ff0a2c909586be3f58307dc89ea7fe4453929ea78b069fd6766597e6553b8

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x73f0b82ea0C7268866Bb39E5a30f3f4E348E3FeB 0x74f96Ed7d11e9028352F44345F4A1D35bDF7d0E4 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59 40232 40232 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url optimism_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 
Transaction hash: 0x898352c6539cb08508ba01af9fd44f07f112dfe2dd5fd71f2174aee170d13e56


# MAINNET
# LENDING CONTRACT DEPLOYMENT
## ARGUMENTS address _issuer, address _weth, uint256 _chainId
forge create src/lendingcontract.sol:CrossChainLendingContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0xf531B8F309Be94191af87605CfBf600D71C2cFe0 40161 --rpc-url mainnet_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
No files changed, compilation skipped
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to: 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030
Transaction hash: 0xf0815221c98b5befd8a8fa182a1da02d973e80d09af410ac6071a540bcfa468e

# DEPOSIT CONTRACT DEPLOYMENT
## ARGUMENTS address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner
forge create src/deposit.sol:AdminDepositContract --constructor-args 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 0x0000000000000000000000000000000000000000 0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030 0xf531B8F309Be94191af87605CfBf600D71C2cFe0 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819 40232 40161 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url mainnet_sepolia --mnemonic ../../keys/sandtest
[🧱] × 
No files changed, compilation skipped
Deployer: 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140
Deployed to:    
Transaction hash: 0x6cc8577db90d36e33d158345868c4b083a67fa2af50a036cb944f295caef173a


    curl -X 'GET' \
    'https://hermes.pyth.network/v2/updates/price/latest?ids%5B%5D=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace&ids%5B%5D=0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784'