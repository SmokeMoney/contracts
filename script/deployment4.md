# Base Deployment
wstETHOracle 0x1195d86C68187C72b9bD6A6602b2881994E36C48
assemblePositionsContract 0x1d936b0dEBBb8C7294C043Ae8332c5e3c3C1aCf4
accountOps 0x54764680B3863A1B72C376Ae92a3cCE65C4DdE69
issuer1NftContract 0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8
spendingContract 0xdaab75CA8E7E3c0F880C4D1727c9c287139b2CA5
depositContract 0x617324745740d7CE92e0E1AB325870F186bDC1a1

# Arb deployment
spendingContract 0x3d4CF5232061744CA5E72eAB6624C96750D71EC2
depositContract 0x3e19BBEe16243F36b331Ce550f3fF2685e972944

# Opt deployment
spendingContract 0xBfE686A5BD487B52943D9E550e42C4910aB33888
depositContract 0x73A257e356Dd6Eb65c2cE9753C67f43Ae3e33A6B

# Eth Sep deployment
spendingContract 0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8
depositContract 0xdaab75CA8E7E3c0F880C4D1727c9c287139b2CA5

# Zora deployment
spendingContract 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6
depositContract 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183

# Blast deployment
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# Morph deployment
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# Setup config = 1
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

## SETUP NFT ADDRESS FOR BELOW
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Setup config = 2
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 2 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Setup config = 3
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# withdrwa funds config = 7
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# add a new chain = 4
forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

## update base script with new deployments
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 4 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 5 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# add a new chain = 4
forge script script/MorphSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 2810 --rpc-url morph_holesky --mnemonic-paths ../../keys/sandtest --broadcast -vvv

## update base script with new deployments
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 4 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 5 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

forge script script/MorphSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 2810 --rpc-url morph_holesky --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

forge create src/SmokeDepositContract.sol:SmokeDepositContract --constructor-args 0x0000000000000000000000000000000000000000 0x14440344256002a5afaA1403EbdAf4bf9a5499E3 0x5300000000000000000000000000000000000011 0xcC3551B5B93733E31AF0c2C7ae4998908CBfB2A1 40245 40290 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url morph_holesky --mnemonic ../../keys/sandtest

forge script script/LineaSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 59144 --rpc-url linea_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
