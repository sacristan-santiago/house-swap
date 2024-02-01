// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

interface IListing {

    struct Listing {
        address owner;
        uint256 price;
        uint256 cancelationPeriod;
    }

     function getListing(uint256 _listingId) external view returns (Listing memory);
}