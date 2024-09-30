# Base Deployment
wstETHOracle 0xBa1D75bd8705f581306425B764FEf4CD767B127b
assemblePositionsContract 0xe21f270E0dF4B56Ed91fEEF45754C1CE3a23f072
accountOps 0x3d4CF5232061744CA5E72eAB6624C96750D71EC2
issuer1NftContract 0x3e19BBEe16243F36b331Ce550f3fF2685e972944
spendingContract 0x67077b70711026CE9d7C3f591D45924264a0c65b
depositContract 0x344DD3EF825c54f836C312CaC66294Fd2ce9F96c

# Arb deployment
spendingContract 0xACdB62538dB30EF5F9Cdb4F7E0640f856708449d
depositContract 0xD5cE1f4A923B90dc9556bC17fBB65781cd71f5aE

# Opt deployment
spendingContract 0xa1971bF0cEa6A6Fe47447914b0AB20118CF7B845
depositContract 0xc6bA506F9E029104896F5B739487b67d4D19c1AD

# Eth Sep deployment
spendingContract 0x78DdB60EbD01D547164F4057C3d36948A66106b6
depositContract 0x88d9872bB7eBA71254faE14E456C095DC1c5C1fA

# Zora deployment
spendingContract 0x73f0b82ea0C7268866Bb39E5a30f3f4E348E3FeB
depositContract 0x74f96Ed7d11e9028352F44345F4A1D35bDF7d0E4

# Blast deployment
spendingContract 0x9b6f6F895a011c2C90857596A1AE2f537B097f52
depositContract 0xF4D2D99b401859c7b825D145Ca76125455154245

# withdrwa funds config = 7
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 7 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# Setup config = 1
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Update NFT and OPS addresses on all the 5 scripts (except first one). 

## SETUP NFT ADDRESS FOR BELOW
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Update addresses on all the 6 scripts, frontend and backend. Don't forget NFT address on backend and frontend

# Setup config = 2
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 2 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Setup config = 3
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ArbSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ZoraSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 999999999 --rpc-url zora_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BlastSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 168587773 --rpc-url blast_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv


# add a new chain = 4
forge script script/MorphSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 2810 --rpc-url morph_holesky --mnemonic-paths ../../keys/sandtest --broadcast -vvv

## update base script with new deployments
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 4 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 5 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

forge script script/MorphSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 3 --chain-id 2810 --rpc-url morph_holesky --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# NFT migration
forge script script/BaseSepoliaMigrate.s.sol:SetupScript --sig "run(uint8)" 8 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# Borrow and Mint
forge script script/BorrowAndMint.s.sol:SetupScript --sig "run(uint8, uint8)" 1 1 --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 0 --broadcast -vvv


# Random shit

forge create src/SmokeDepositContract.sol:SmokeDepositContract --constructor-args 0x0000000000000000000000000000000000000000 0x14440344256002a5afaA1403EbdAf4bf9a5499E3 0x5300000000000000000000000000000000000011 0xcC3551B5B93733E31AF0c2C7ae4998908CBfB2A1 40245 40290 0x6EDCE65403992e310A62460808c4b910D972f10f 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 --rpc-url morph_holesky --mnemonic ../../keys/sandtest

forge script script/LineaSepoliaSetup.s.sol:SetupScript --sig "run(uint8)" 1 --chain-id 59144 --rpc-url linea_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Export ABIs to frontend and backend

forge inspect src/SmokeSpendingContract.sol:SmokeSpendingContract abi > ../vite-react/src/abi/SmokeSpendingContract.abi.json
forge inspect src/CoreNFTContract.sol:CoreNFTContract abi > ../vite-react/src/abi/CoreNFTContract.abi.json
forge inspect src/SmokeDepositContract.sol:SmokeDepositContract abi > ../vite-react/src/abi/SmokeDepositContract.abi.json
forge inspect src/OperationsContract.sol:OperationsContract abi > ../vite-react/src/abi/OperationsContract.abi.json

forge inspect src/SmokeSpendingContract.sol:SmokeSpendingContract abi > ../backend/src/abi/SmokeSpendingContract.abi.json
forge inspect src/CoreNFTContract.sol:CoreNFTContract abi > ../backend/src/abi/CoreNFTContract.abi.json
forge inspect src/SmokeDepositContract.sol:SmokeDepositContract abi > ../backend/src/abi/SmokeDepositContract.abi.json
forge inspect src/OperationsContract.sol:OperationsContract abi > ../backend/src/abi/OperationsContract.abi.json
forge inspect lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:ERC20 abi > ../backend/src/abi/ERC20.abi.json