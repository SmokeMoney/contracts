    // SPDX-License-Identifier: UNLICENSED
    pragma solidity ^0.8.13;

    import "forge-std/Test.sol";
    import "../src/deposit.sol";
    import "../src/nftaccounts.sol";
    import "../src/weth.sol";
    import "../src/siggen.sol";
    import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
    import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

    contract MockERC20 is ERC20 {
        constructor() ERC20("Mock Token", "MTK") {
            _mint(msg.sender, 1000000 * 10**18);
        }
    }

    contract DepositTest is Test {
        using ECDSA for bytes32;

        AdminDepositContract public deposit;
        CrossChainLendingAccount public nftContract;
        SignatureGenerator public siggen;
        WETH public weth;
        MockERC20 public mockToken;
        address public issuer;
        address public user;
        address public user2;
        uint256 internal issuerPk;
        uint256 public adminChainIdReal;

        function setUp() public {
            (issuer, issuerPk) = makeAddrAndKey("issuer");

            // issuer = address(1);
            user = address(2);
            user2 = address(3);
            adminChainIdReal = 31337;
            
            vm.startPrank(issuer);
            nftContract = new CrossChainLendingAccount("AutoGas", "OG", issuer);
            // mockToken = new MockERC20();
            weth = new WETH();
            siggen = new SignatureGenerator();
            deposit = new AdminDepositContract(issuer, address(nftContract));
            deposit.addSupportedToken(address(weth));

            nftContract.approveChain(adminChainIdReal); // Adding a supported chain
            nftContract.setDepositContract(adminChainIdReal, address(deposit)); // Adding the deposit contract
            vm.stopPrank();

            assertEq(nftContract.adminChainId(), adminChainIdReal);

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
            uint256 tokenId = nftContract.mint();
            deposit.deposit(address(weth), tokenId, 1 * 10**18);
            vm.stopPrank();

            assertEq(deposit.getDepositAmount(address(weth), tokenId), 1 * 10**18);
        }

        // Add more test cases here, for example:
        function testWithdraw() public {
            // Mint an NFT for the user
            vm.startPrank(user);
            uint256 tokenId = nftContract.mint();
            deposit.deposit(address(weth), tokenId, 1 * 10**18);
            vm.stopPrank();

            uint timestamp = vm.unixTime();

            vm.startPrank(issuer);
            bytes32 digest = keccak256(abi.encodePacked(user, address(weth), tokenId, uint256(0.1 * 10**18), uint256(adminChainIdReal), timestamp, uint256(0)));
            bytes32 hash = siggen.getEthSignedMessageHash(digest);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);  
            bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
            vm.stopPrank();     

            vm.startPrank(user);
            nftContract.withdraw(address(weth), tokenId, 0.1 * 10**18, adminChainIdReal, timestamp, 0, signature);
            vm.stopPrank();
            assertEq(deposit.getDepositAmount(address(weth), tokenId), 0.9 * 10**18);
        }

        function testBorrow() public {
            // Mint an NFT for the user
            vm.startPrank(user);
            uint256 tokenId = nftContract.mint();
            
        }

        function testForcedWithdrawal() public {
            // Implement forced withdrawal test
        }
    }