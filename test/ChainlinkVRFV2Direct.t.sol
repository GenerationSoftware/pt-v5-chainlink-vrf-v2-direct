// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ChainlinkVRFV2Direct } from "../src/ChainlinkVRFV2Direct.sol";
import { VRFV2Wrapper } from "chainlink/vrf/VRFV2Wrapper.sol";
import { LinkTokenInterface } from "chainlink/interfaces/LinkTokenInterface.sol";

contract ChainlinkVRFV2DirectTest is Test {

  /* ============ Events ============ */
  event RandomNumberRequested(uint32 indexed requestId, address indexed sender);
  event SetCallbackGasLimit(uint32 callbackGasLimit);
  event SetRequestConfirmations(uint16 requestConfirmations);

  /* ============ Custom Errors ============ */

  /// @notice Thrown when the LINK token contract address is set to the zero address.
  error LinkTokenZeroAddress();

  /// @notice Thrown when the VRFV2Wrapper address is set to the zero address.
  error VRFV2WrapperZeroAddress();

  /// @notice Thrown when the callback gas limit is set to zero.
  error CallbackGasLimitZero();

  /// @notice Thrown when the number of request confirmations is set to zero.
  error RequestConfirmationsZero();

  /// @notice Thrown when the chainlink VRF request ID does not match any stored request IDs.
  /// @param vrfRequestId The chainlink ID for the VRF Request
  error InvalidVrfRequestId(uint256 vrfRequestId);

  /* ============ Global Variables ============ */
  uint256 public mainnetFork;

  address public linkMainnet = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
  address public wrapperMainnet = 0x5A861794B927983406fCE1D062e00b9368d97Df6;
  address public mainnetLinkHolder = 0xD48133C96C5FE8d41D0cbD598F65bf4548941e27; // Just an address that has a lot of mainnet link that we can spoof a transfer from

  uint32 public callbackGasLimit = 1_000_000;
  uint16 public requestConfirmations = 3;

  ChainlinkVRFV2Direct public vrfDirect;

  /* ============ Set Up ============ */
  function setUp() public {
    mainnetFork = vm.createFork(vm.rpcUrl("mainnet"), 17_917_752);
  }

  /* ============ requestRandomNumber() ============ */
  function testForkRequestRandomNumber() external {
    useMainnet();

    // Get fee
    (address feeToken, uint256 requestFee) = vrfDirect.getRequestFee();
    assertEq(feeToken, linkMainnet);
    assertGt(requestFee, 0);

    // Empty VRF LINK balance
    uint256 existingLinkBalance = LinkTokenInterface(linkMainnet).balanceOf(address(vrfDirect));
    if (existingLinkBalance > 0) {
      vm.startPrank(address(vrfDirect));
      LinkTokenInterface(linkMainnet).transfer(address(this), existingLinkBalance);
      vm.stopPrank();
    }

    // Transfer exact LINK fee
    transferMainnetLinkTo(address(vrfDirect), requestFee);

    // Start request:
    vm.expectEmit();
    emit RandomNumberRequested(1, address(this));
    (uint32 requestId, uint32 lockBlock) = vrfDirect.requestRandomNumber();
    assertEq(requestId, 1);
    assertEq(lockBlock, block.number);

    // Check new balance
    uint256 vrfDirectBalance = LinkTokenInterface(linkMainnet).balanceOf(address(vrfDirect));
    assertEq(vrfDirectBalance, 0);
  }

  /* ============ isRequestComplete() ============ */
  function testIsRequestComplete() external {
    useMainnet();
    (uint32 _requestId, uint32 _lockBlock) = requestRandomNumberMainnet();
    uint256 _wrapperRequestId = VRFV2Wrapper(wrapperMainnet).lastRequestId();
    assertEq(vrfDirect.isRequestComplete(_requestId), false);

    // Fulfill randomness
    fulfillRequest(_wrapperRequestId, _lockBlock, 12345);

    // Check again
    assertEq(vrfDirect.isRequestComplete(_requestId), true);
  }

  /* ============ completedAt() ============ */
  function testCompletedAt() external {
    useMainnet();
    (uint32 _requestId, uint32 _lockBlock) = requestRandomNumberMainnet();
    uint256 _wrapperRequestId = VRFV2Wrapper(wrapperMainnet).lastRequestId();
    assertEq(vrfDirect.completedAt(_requestId), 0);

    // Fulfill randomness
    fulfillRequest(_wrapperRequestId, _lockBlock, 12345);

    // Check again
    uint64 timestamp = uint64(block.timestamp);
    assertEq(vrfDirect.completedAt(_requestId), timestamp);
  }

  /* ============ randomNumber() ============ */
  function testRandomNumber() external {
    useMainnet();
    (uint32 _requestId, uint32 _lockBlock) = requestRandomNumberMainnet();
    uint256 _wrapperRequestId = VRFV2Wrapper(wrapperMainnet).lastRequestId();
    assertEq(vrfDirect.randomNumber(_requestId), 0);

    // Fulfill randomness
    fulfillRequest(_wrapperRequestId, _lockBlock, 12345);

    // Check again
    assertEq(vrfDirect.randomNumber(_requestId), 12345);
  }

  /* ============ getLastRequestId() ============ */
  function testGetLastRequestId() external {
    useMainnet();
    assertEq(vrfDirect.getLastRequestId(), 0);
    (uint32 _requestId,) = requestRandomNumberMainnet();
    assertEq(vrfDirect.getLastRequestId(), _requestId);
    assertEq(_requestId, 1);
  }

  /* ============ setCallbackGasLimit() ============ */
  function testSetCallbackGasLimit() external {
    useMainnet();
    assertEq(vrfDirect.getCallbackGasLimit(), callbackGasLimit);

    uint32 _newLimit = 999_999;
    assertEq(_newLimit == callbackGasLimit, false);
    vm.expectEmit();
    emit SetCallbackGasLimit(_newLimit);
    vrfDirect.setCallbackGasLimit(_newLimit);

    assertEq(vrfDirect.getCallbackGasLimit(), _newLimit);
  }

  function testSetCallbackGasLimit_NotOwner() external {
    useMainnet();
    vm.startPrank(address(5));
    vm.expectRevert("Ownable/caller-not-owner");
    vrfDirect.setCallbackGasLimit(1_000);
    vm.stopPrank();
  }

  function testSetCallbackGasLimit_Zero() external {
    useMainnet();
    vm.expectRevert(abi.encodeWithSelector(CallbackGasLimitZero.selector));
    vrfDirect.setCallbackGasLimit(0);
  }

  /* ============ setRequestConfirmations() ============ */
  function testSetRequestConfirmations() external {
    useMainnet();
    assertEq(vrfDirect.getRequestConfirmations(), requestConfirmations);

    uint16 _newConfirmations = 10;
    assertEq(_newConfirmations == requestConfirmations, false);
    vm.expectEmit();
    emit SetRequestConfirmations(_newConfirmations);
    vrfDirect.setRequestConfirmations(_newConfirmations);

    assertEq(vrfDirect.getRequestConfirmations(), _newConfirmations);
  }

  function testSetRequestConfirmations_NotOwner() external {
    useMainnet();
    vm.startPrank(address(5));
    vm.expectRevert("Ownable/caller-not-owner");
    vrfDirect.setRequestConfirmations(10);
    vm.stopPrank();
  }

  function testSetRequestConfirmations_Zero() external {
    useMainnet();
    vm.expectRevert(abi.encodeWithSelector(RequestConfirmationsZero.selector));
    vrfDirect.setRequestConfirmations(0);
  }

  /* ============ fulfillRandomWords() ============ */
  function testFulfillRandomWords_InvalidRequestId() external {
    useMainnet();
    requestRandomNumberMainnet();
    uint256 _wrapperRequestId = VRFV2Wrapper(wrapperMainnet).lastRequestId();
    uint256 _badId = _wrapperRequestId + 1;

    vm.startPrank(wrapperMainnet);
    uint256[] memory _randomWords = new uint256[](1);
    _randomWords[0] = 12345;
    vm.expectRevert(abi.encodeWithSelector(InvalidVrfRequestId.selector, _badId));
    vrfDirect.rawFulfillRandomWords(_badId, _randomWords);
    vm.stopPrank();
  }

  /* ============ vrfV2Wrapper() ============ */
  function testVrfV2Wrapper() external {
    useMainnet();
    assertEq(address(vrfDirect.vrfV2Wrapper()), address(wrapperMainnet));
  }

  /* ============ Helpers ============ */

  /// @dev Run at the beginning of each fork test
  function useMainnet() public {
    vm.selectFork(mainnetFork);
    vrfDirect = new ChainlinkVRFV2Direct(
      address(this),
      VRFV2Wrapper(address(wrapperMainnet)),
      callbackGasLimit,
      requestConfirmations
    );
  }

  /// @notice Helper that spoofs a mainnet LINK transfer to the given address
  function transferMainnetLinkTo(address to, uint256 value) public {
    vm.selectFork(mainnetFork);
    vm.startPrank(mainnetLinkHolder);
    LinkTokenInterface(linkMainnet).transfer(to, value);
    vm.stopPrank();
  }

  /// @notice Helper to request random number on mainnet fork
  function requestRandomNumberMainnet() public returns (uint32 requestId, uint32 lockBlock) {
    (, uint256 requestFee) = vrfDirect.getRequestFee();
    transferMainnetLinkTo(address(vrfDirect), requestFee);
    return vrfDirect.requestRandomNumber();
  }

  /// @notice Helper to fulfill an RNG request
  function fulfillRequest(uint256 _wrapperRequestId, uint32 _lockBlock, uint256 _randomNumber) public {
    vm.roll(_lockBlock + requestConfirmations);
    vm.startPrank(wrapperMainnet);
    uint256[] memory _randomWords = new uint256[](1);
    _randomWords[0] = _randomNumber;
    vrfDirect.rawFulfillRandomWords(_wrapperRequestId, _randomWords);
    vm.stopPrank();
  }

}
