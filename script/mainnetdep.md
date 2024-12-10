# base
wstETHOracle 0x14440344256002a5afaA1403EbdAf4bf9a5499E3
assemblePositionsContract 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6
accountOps 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183
issuer1NftContract 0x794F11F77cd0D4eE60885A1a1857d796f0D08fd7
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# arbitrum
spendingContract 0x9cA9D67f613c50741E30e5Ef88418891e254604d
depositContract 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59

# optimism
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# blast
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# scroll
spendingContract 0x9cA9D67f613c50741E30e5Ef88418891e254604d
depositContract 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59

# base account ops
forge script script/BaseSetup.s.sol:SetupScript --sig "run(uint8)" 1 --rpc-url base --mnemonic-paths ../../keys/sandtest --broadcast -vv

forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 101 --rpc-url arbitrum --mnemonic-paths ../../keys/sandtest --broadcast -vvvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 102 --rpc-url optimism --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 105 --rpc-url blast --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 106 --rpc-url scroll --mnemonic-paths ../../keys/sandtest --broadcast -vvv

# config 3 
forge script script/BaseSetup.s.sol:SetupScript --sig "run(uint8)" 3 --rpc-url base --mnemonic-paths ../../keys/sandtest  --mnemonic-indexes 3 --broadcast -vv

forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 3 101 --rpc-url arbitrum --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 3 --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 3 102 --rpc-url optimism --mnemonic-paths ../../keys/sandtest --mnemonic-indexes 3 --broadcast -vvv

forge verify-contract --chain-id 42161 --constructor-args 0x0000000000000000000000000000000000000000 0x9cA9D67f613c50741E30e5Ef88418891e254604d 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 0x0fBcbaEA96Ce0cF7Ee00A8c19c3ab6f5Dc8E1921 30184 30110 0x1a44076050125825900e736c501f859c50fE728c 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140 

forge verify-contract --chain-id 42161 --constructor-args 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000009ca9d67f613c50741e30e5ef88418891e254604d00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000fbcbaea96ce0cf7ee00a8c19c3ab6f5dc8e192100000000000000000000000000000000000000000000000000000000000075e8000000000000000000000000000000000000000000000000000000000000759e0000000000000000000000001a44076050125825900e736c501f859c50fe728c00000000000000000000000003773f85756acac65a869e89e3b7b2fcda6be140000000000000000000000000eebe5e1bd522bbd9a64f28d923c0680f89db5c59 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59 src/SmokeDepositContract.sol:SmokeDepositContract 