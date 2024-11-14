// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/interfaces/IERC20.sol";
import "src/interfaces/IUMA.sol";

interface IHooks {
    function priceProposed(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory question
    ) external;

    function priceDisputed(
        bytes32,
        uint256,
        bytes memory question,
        uint256 refund
    ) external;

    function priceSettled(
        bytes32,
        uint256,
        bytes memory question,
        int256 price
    ) external;
}

contract UMA is IUMA {
    bool constant public IS_SCRIPT = true;

    mapping(bytes => Request) internal _requests;
    mapping(bytes => address) internal _requester;

    event PriceRequested(address indexed requester, bytes question);

    uint x;


    function requestPrice(
        bytes32,
        uint256,
        bytes memory question,
        address currency,
        uint256 reward
    ) external returns (uint256 totalBond){

        IERC20(currency).transferFrom(msg.sender, address(this), reward);

        _requester[question] = msg.sender;
        _requests[question].currency = currency;

        emit PriceRequested(msg.sender, question);
        return 500 ether;
    }

    function proposePrice(bytes calldata question, uint256 price) external {
        require(_requests[question].proposedPrice == 0, "ALREADY PROPOSED");

        _requests[question].proposedPrice = int(price);

        IHooks(_requester[question]).priceProposed(0, 0, question);
    }

    function disputePrice(bytes calldata question) external {
        require(_requests[question].proposedPrice != 0, "NOT PROPOSED");

        IERC20(_requests[question].currency).transfer(_requester[question], 5 ether);

        IHooks(_requester[question]).priceDisputed(0, 0, question, 5 ether);
    }

    function settlePrice(bytes calldata question, uint256 price) external {
        require(_requests[question].proposedPrice != 0, "NOT PROPOSED");

        _requests[question].proposedPrice = int(price);

        IHooks(_requester[question]).priceSettled(0, 0, question, int(price));
    }

    function setCustomLiveness(
        bytes32,
        uint256,
        bytes memory,
        uint256
    ) external {
        ++x;
    }

    function setEventBased(
        bytes32,
        uint256,
        bytes memory
    ) external {
        ++x;
    }

    function setCallbacks(
        bytes32,
        uint256,
        bytes memory,
        bool,
        bool,
        bool
    ) external {
        ++x;
    }

    function requests(bytes32) external pure returns (Request memory request) {
        return request;
    }
}