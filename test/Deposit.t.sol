    // SPDX-License-Identifier: UNLICENSED
    pragma solidity ^0.8.13;

    import "forge-std/Test.sol";
    import "../src/deposit.sol";
    import "../src/corenft.sol";
    import "../src/accountops.sol";
    import "../src/weth.sol";
    import "../src/siggen.sol";
    import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
    import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
    import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";   

    contract MockERC20 is ERC20 {
        constructor() ERC20("Mock Token", "MTK") {
            _mint(msg.sender, 1000000 * 10**18);
        }
    }

    contract DepositTest is TestHelperOz5 {
        using ECDSA for bytes32;

        AdminDepositContract public deposit;
        CoreNFTContract public nftContract;
        OperationsContract public accountOps;
        SignatureGenerator public siggen;
        WETH public weth;
        MockERC20 public mockToken;
        address public issuer;
        address public user;
        address public user2;
        uint256 internal issuerPk;

        uint32 aEid = 1;
        uint32 bEid = 2;
        function setUp() public virtual override {
            (issuer, issuerPk) = makeAddrAndKey("issuer");

            // issuer = address(1);
            user = address(2);
            user2 = address(3);
            super.setUp();
            setUpEndpoints(2, LibraryType.UltraLightNode);
            
            vm.startPrank(issuer);

            nftContract = new CoreNFTContract("AutoGas", "OG", issuer, address(this), 0.02 * 1e18, 10);
            accountOps = new OperationsContract(address(nftContract), address(endpoints[aEid]), address(0), issuer, issuer, 1);
            weth = new WETH();
            siggen = new SignatureGenerator();
            deposit = new AdminDepositContract(address(accountOps), address(0), address(0), address(0), 1, aEid, address(endpoints[aEid]), issuer, issuer);
            deposit.addSupportedToken(address(weth));

            nftContract.approveChain(aEid); // Adding a supported chain
            accountOps.setDepositContract(aEid, address(deposit)); // Adding the deposit contract
            vm.stopPrank();

            assertEq(accountOps.adminChainId(), aEid);

            // The user is getting some WETH
            vm.deal(user, 100 ether);
            vm.deal(issuer, 100 ether);
            vm.startPrank(user);
            uint256 amount = 10 ether;
            weth.deposit{value: amount}();
            weth.approve(address(deposit), 10 * 10**18);
            vm.stopPrank();
        }

        function testDeposit() public {
            // Mint an NFT for the user
            vm.startPrank(user);
            uint256 tokenId = nftContract.mint{value:0.02*1e18}();
            deposit.deposit(address(weth), tokenId, 1 * 10**18);
            vm.stopPrank();

            assertEq(deposit.getDepositAmount(address(weth), tokenId), 1 * 10**18);
        }

        // Add more test cases here, for example:
        function testWithdraw() public {
            // Mint an NFT for the user
            vm.startPrank(user);
            uint256 tokenId = nftContract.mint{value:0.02*1e18}();
            deposit.deposit(address(weth), tokenId, 1 * 10**18);
            vm.stopPrank();

            uint timestamp = vm.unixTime();

            vm.startPrank(issuer);
            bytes32 digest = keccak256(abi.encodePacked(user, address(weth), tokenId, uint256(0.1 * 10**18), uint32(aEid), timestamp, uint256(1)));
            bytes32 hash = siggen.getEthSignedMessageHash(digest);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);  
            bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
            vm.stopPrank();     

            bytes memory options = new bytes(0);
            vm.startPrank(user);
            accountOps.withdraw(address(weth), tokenId, 0.1 * 10**18, aEid, timestamp, 1, signature, options, address(user));
            vm.stopPrank();
            assertEq(deposit.getDepositAmount(address(weth), tokenId), 0.9 * 10**18);
        }
    }