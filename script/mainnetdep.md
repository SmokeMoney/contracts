# base
wstETHOracle 0x14440344256002a5afaA1403EbdAf4bf9a5499E3
assemblePositionsContract 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6
accountOps 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183
issuer1NftContract 0x85a5A8AfF78df7097907952A366C6F86F3d4Aa10
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# arbitrum
spendingContract 0xf430ac9B73c5fb875d8350A300E95049a19CAbb1
depositContract 0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B

# optimism
spendingContract 0x14440344256002a5afaA1403EbdAf4bf9a5499E3
depositContract 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6

# base account ops
forge script script/BaseSetup.s.sol:SetupScript --sig "run(uint8)" 1 --rpc-url base --mnemonic-paths ../../keys/sandtest --broadcast -vv

forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 101 --rpc-url arbitrum --mnemonic-paths ../../keys/sandtest --broadcast -vvvv

forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 102 --rpc-url optimism --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 104 --rpc-url zora --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 105 --rpc-url blast --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 106 --rpc-url scroll --mnemonic-paths ../../keys/sandtest --broadcast -vvv
forge script script/SpokeChainSetup.s.sol:SetupScript --sig "run(uint8, uint8)" 1 105 --rpc-url blast --mnemonic-paths ../../keys/sandtest --broadcast -vvv