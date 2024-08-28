# Base deployment
wstETHOracle 0x3286d223EBc31862FD7C70Ece4EB944B3F3A033E
assemblePositionsContract 0xdE56a670Bc19dbEC947bb0A354C20a327C0dE4b3
accountOps 0x4AA5F077688ba0d53836A3B9E9FDC3bFB16B1362
issuer1NftContract 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A
spendingContract 0xF1dE39102db79151F20cAC04D3A5DCe45a3D8Dbc
depositContract 0x17086242C5EcC58a7cBb828312911c782CA6981e

# Arb deployment
spendingContract 0x9F1b8D30D9e86B3bF65fa9f91722B4A3E9802382
depositContract 0xced5018D9C2d1088907581A7C24c670667F0079b

# Opt Deployment
spendingContract 0x4AA5F077688ba0d53836A3B9E9FDC3bFB16B1362
depositContract 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A

# Sepolia deployment
spendingContract 0xC4e5BC86C3CAEd72dB41e62675f27b239Cb23bc6
depositContract 0xB48F7a8aD1302C77C75acd3BB98f416000A99aad 

# Setup config = 1
forge script script/ArbSepoliaSetup.s.sol:SetupScript --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Setup config = 3
forge script script/ArbSepoliaSetup.s.sol:SetupScript --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

# Setup config = 2
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Resending stuck txns
cast send 0x17086242C5EcC58a7cBb828312911c782CA6981e "addSupportedToken(address,address)" 0x4200000000000000000000000000000000000006 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-index 1 -- --resend --priority-gas-price 0.02067243 -vvv
cast send 0x17086242C5EcC58a7cBb828312911c782CA6981e "addSupportedToken(address,address)" 0x14440344256002a5afaA1403EbdAf4bf9a5499E3 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A --rpc-url base_sepolia --mnemonic-path ../../keys/sandtest --mnemonic-index 1 -- --resend --priority-gas-price 0.02067243 -vvv

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
