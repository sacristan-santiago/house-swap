// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import {IListing} from "../interfaces/IListing.sol";

contract Listings is IListing {
    uint256 listingCount;

    mapping (uint256 listingId => Listing) public listings;

    event newListing(uint256 listingId, address host);

    function createListing (uint256 _price, uint256 _cancelationPeriod) public {
        listingCount++;

        listings[listingCount] = Listing({
            owner: msg.sender,
            price: _price,
            cancelationPeriod: _cancelationPeriod
        });

        emit newListing(listingCount, msg.sender);
    }

    function getListing(uint256 _listingId) external view returns (Listing memory) {
        return listings[_listingId];
    }
}