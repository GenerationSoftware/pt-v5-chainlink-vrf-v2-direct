// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/ChainlinkVRFV2DirectRngAuctionHelper.sol";
import { ChainlinkVRFV2Direct } from "../src/ChainlinkVRFV2Direct.sol";

import { ERC20Mintable } from "./mock/ERC20Mintable.sol";
import { IRngAuction } from "../src/interfaces/IRngAuction.sol";
import { RNGInterface } from "rng-contracts/RNGInterface.sol";

contract ChainlinkVRFV2DirectRngAuctionHelperTest is Test {

  /* ============ Variables ============ */
  ChainlinkVRFV2DirectRngAuctionHelper public vrfHelper;
  ChainlinkVRFV2Direct public vrfDirect;
  IRngAuction public rngAuction;
  ERC20Mintable public rngFeeToken;

  /* ============ Setup ============ */
  function setUp() public {
    vm.warp(0);

    rngFeeToken = new ERC20Mintable("RNG Fee Token", "RNGFT");

    rngAuction = IRngAuction(makeAddr("rngAuction"));
    vm.etch(address(rngAuction), "rngAuction");

    vrfDirect = ChainlinkVRFV2Direct(makeAddr("vrfDirect"));
    vm.etch(address(vrfDirect), "vrfDirect");

    vrfHelper = new ChainlinkVRFV2DirectRngAuctionHelper(vrfDirect, rngAuction);
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