// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/ChainlinkVRFV2DirectRngAuctionHelper.sol";
import { ChainlinkVRFV2Direct } from "../src/ChainlinkVRFV2Direct.sol";

import { ERC20Mintable } from "./mock/ERC20Mintable.sol";
import { IRngAuction } from "../src/interfaces/IRngAuction.sol";
import { RNGInterface } from "rng-contracts/RNGInterface.sol";

import { VRFV2Wrapper } from "chainlink/vrf/VRFV2Wrapper.sol";
import { LinkTokenInterface } from "chainlink/interfaces/LinkTokenInterface.sol";

contract ChainlinkVRFV2DirectRngAuctionHelperTest is Test {

  /* ============ Variables ============ */
  ChainlinkVRFV2DirectRngAuctionHelper public vrfHelper;
  ChainlinkVRFV2Direct public vrfDirect;
  IRngAuction public rngAuction;
  ERC20Mintable public rngFeeToken;

  uint256 public mainnetFork;
  
  address public linkMainnet = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
  address public wrapperMainnet = 0x5A861794B927983406fCE1D062e00b9368d97Df6;

  /* ============ Setup ============ */
  function setUp() public {
    vm.warp(0);

    rngFeeToken = new ERC20Mintable("RNG Fee Token", "RNGFT");

    rngAuction = IRngAuction(makeAddr("rngAuction"));
    vm.etch(address(rngAuction), "rngAuction");

    vrfDirect = ChainlinkVRFV2Direct(makeAddr("vrfDirect"));
    vm.etch(address(vrfDirect), "vrfDirect");

    vrfHelper = new ChainlinkVRFV2DirectRngAuctionHelper(vrfDirect, rngAuction);

    // create mainnet fork
    vm.createFork(vm.rpcUrl("mainnet"), 17_917_752);
  }

  /* ============ Tests ============ */

  /// @dev Tests if the constructor will revert if the VRF address is the zero address.
  function testConstructorZeroVrfAddress() public {
    vm.expectRevert(abi.encodeWithSelector(ChainlinkVRFV2DirectZeroAddress.selector));
    new ChainlinkVRFV2DirectRngAuctionHelper(ChainlinkVRFV2Direct(address(0)), rngAuction);
  }

  /// @dev Tests if the constructor will revert if the RNG Auction address is the zero address.
  function testConstructorZeroRngAuctionAddress() public {
    vm.expectRevert(abi.encodeWithSelector(RngAuctionZeroAddress.selector));
    new ChainlinkVRFV2DirectRngAuctionHelper(vrfDirect, IRngAuction(address(0)));
  }

  /// @dev Tests if the ChainlinkVRFV2Direct contract address is public to read.
  function testReadVrfAddress() public {
    assertEq(address(vrfHelper.chainlinkVrfV2Direct()), address(vrfDirect));
  }

  /// @dev Tests if the RNG Auction contract address is public to read.
  function testReadAuctionAddress() public {
    assertEq(address(vrfHelper.rngAuction()), address(rngAuction));
  }

  /// @dev Tests if the transfer of fees works as intended before the startRngRequest call
  function testTransferFeeAndStartRngRequest() public {
    uint256 _fee = 5000;

    // mocks
    _mockRngAuctionGetNextRngService(rngAuction, vrfDirect);
    _mockChainlinkVrfV2DirectGetRequestFee(vrfDirect, address(rngFeeToken), _fee);
    _mockRngAuctionStartRngRequest(rngAuction, address(this));
    
    // mint fee to this address
    rngFeeToken.mint(address(this), _fee);

    // test
    rngFeeToken.approve(address(vrfHelper), _fee);
    vrfHelper.transferFeeAndStartRngRequest(address(this));
    assertEq(rngFeeToken.balanceOf(address(this)), 0);
    assertEq(rngFeeToken.balanceOf(address(vrfDirect)), _fee);
  }

  /// @dev Tests if revert when RngService is no longer the expected chainlink VRF address.
  function testTransferFeeAndStartRngRequestRngServiceNotActive() public {
    uint256 _fee = 5000;

    // mocks
    _mockRngAuctionGetNextRngService(rngAuction, RNGInterface(address(2))); // mock to different address
    _mockRngAuctionGetNextRngService(rngAuction, RNGInterface(address(2))); // mock to different address (second call)
    _mockChainlinkVrfV2DirectGetRequestFee(vrfDirect, address(rngFeeToken), _fee);
    _mockRngAuctionStartRngRequest(rngAuction, address(this));
    
    // mint fee to this address
    rngFeeToken.mint(address(this), _fee);

    // test
    rngFeeToken.approve(address(vrfHelper), _fee);
    vm.expectRevert(abi.encodeWithSelector(RngServiceNotActive.selector, address(vrfDirect), address(2)));
    vrfHelper.transferFeeAndStartRngRequest(address(this));
  }

  /// @dev Tests if the transfer of fees fails if not approved.
  function testTransferFeeAndStartRngRequestNotApproved() public {
    uint256 _fee = 5000;

    // mocks
    _mockRngAuctionGetNextRngService(rngAuction, vrfDirect);
    _mockChainlinkVrfV2DirectGetRequestFee(vrfDirect, address(rngFeeToken), _fee);
    _mockRngAuctionStartRngRequest(rngAuction, address(this));
    
    // mint fee to this address
    rngFeeToken.mint(address(this), _fee);

    // test
    rngFeeToken.approve(address(vrfHelper), 0); // zero approval
    vm.expectRevert("ERC20: insufficient allowance");
    vrfHelper.transferFeeAndStartRngRequest(address(this));
  }

  /// @dev Tests if the transfer of fees fails if not enough balance.
  function testTransferFeeAndStartRngRequestNotEnoughBalance() public {
    uint256 _fee = 5000;

    // mocks
    _mockRngAuctionGetNextRngService(rngAuction, vrfDirect);
    _mockChainlinkVrfV2DirectGetRequestFee(vrfDirect, address(rngFeeToken), _fee);
    _mockRngAuctionStartRngRequest(rngAuction, address(this));
    
    // burn all tokens
    rngFeeToken.transfer(address(1), rngFeeToken.balanceOf(address(this)));

    // test
    rngFeeToken.approve(address(vrfHelper), _fee);
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    vrfHelper.transferFeeAndStartRngRequest(address(this));
  }

  function testForkEstimateRequestFee() public {

    // mainnet fork setup
    vm.selectFork(mainnetFork);
    vrfDirect = new ChainlinkVRFV2Direct(
      address(this),
      VRFV2Wrapper(address(wrapperMainnet)),
      1_000_000,
      3
    );
    vrfHelper = new ChainlinkVRFV2DirectRngAuctionHelper(vrfDirect, rngAuction);

    // Get actual fee if called during this TX
    (address linkActualAddress, uint256 feeActual) = vrfDirect.getRequestFee();

    // test that `estimateRequestFee` returns the same fee as `getRequestFee` when the same gas price is used
    (address linkAddressEstimateSame, uint256 feeEstimateSame) = vrfHelper.estimateRequestFee(tx.gasprice);
    assertEq(linkAddressEstimateSame, linkActualAddress);
    assertEq(feeEstimateSame, feeActual);

    // test that `estimateRequestFee` returns a higher fee than `getRequestFee` when a higher gas price is used
    (address linkAddressEstimateHigher, uint256 feeEstimateHigher) = vrfHelper.estimateRequestFee(tx.gasprice + 10);
    assertEq(linkAddressEstimateHigher, linkActualAddress);
    assertGt(feeEstimateHigher, feeActual);
  }

  /* ============ Mocks ============ */

  function _mockRngAuctionGetNextRngService(IRngAuction _rngAuction, RNGInterface _nextRngInterface) internal {
    vm.mockCall(
      address(_rngAuction),
      abi.encodeWithSelector(IRngAuction.getNextRngService.selector),
      abi.encode(_nextRngInterface)
    );
  }

  function _mockRngAuctionStartRngRequest(IRngAuction _rngAuction, address _rewardRecipient) internal {
    vm.mockCall(
      address(_rngAuction),
      abi.encodeWithSelector(IRngAuction.startRngRequest.selector, _rewardRecipient),
      abi.encode(0)
    );
  }

  function _mockChainlinkVrfV2DirectGetRequestFee(ChainlinkVRFV2Direct _chainlinkVrfV2Direct, address _feeToken, uint256 _fee) internal {
    vm.mockCall(
      address(_chainlinkVrfV2Direct),
      abi.encodeWithSelector(ChainlinkVRFV2Direct.getRequestFee.selector),
      abi.encode(_feeToken, _fee)
    );
  }

}