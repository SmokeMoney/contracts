# BASE Deployment
wstETHOracle 0xb4b083629b5173aE8f29544F637CfE6761F7fC6c
assemblePositionsContract 0xBF9CB56e2e927AEF651723d07e1eC95dC3F9764d
accountOps 0x269488db82d434dC2E08e3B6f428BD1FF90C4325
issuer1NftContract 0x6d5ecc0aa8DcE64045b1053A2480D82A61Ad86Bc
spendingContract 0xa2926E337A8c0B366ba7c263F6EbBb018d306aF4
depositContract 0x74Ee076c2ce51e081375B3f106e525646697809d

# Arb deployment
spendingContract 0xBFa2901F914A6a4f005D85181349F50a4981A776
depositContract 0x873f2667Bd24982626a7e4A12d71491b89812e6b

# Opt deployment
spendingContract 0x6698928094A6Ac338eA71D66a9Bcdba028B81d4F
depositContract 0x0F9F8AbFD3689A76916e7d19A8573F0899E0Da14

# Sep deployment
spendingContract 0x99741c2f93Df59e8c3D957998265b977e4b6CA72
depositContract 0x2d5905509ee73e8abf0fd50988EE5cEd19b2ca90


# Setup config = 1
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/ArbSepoliaSetup.s.sol:SetupScript --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv


# Setup config = 2
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# Setup config = 3
forge script script/BaseSepoliaSetup.s.sol:SetupScript --chain-id 84532 --rpc-url base_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/ArbSepoliaSetup.s.sol:SetupScript --chain-id 421614 --rpc-url arbitrum_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/OptSepoliaSetup.s.sol:SetupScript --chain-id 11155420 --rpc-url optimism_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv
forge script script/SepoliaSetup.s.sol:SetupScript --chain-id 11155111 --rpc-url mainnet_sepolia --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 1 --broadcast -vvv

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
