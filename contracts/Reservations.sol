// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IListing} from "../interfaces/IListing.sol";
import {Escrow} from "./Escrow.sol";

contract Reservations {
    //Variables
    address public owner = msg.sender;
    IListing internal listingContract;
    AggregatorV3Interface internal aggregator;
    Escrow escrow;
    uint256 public reservationCount;
    uint256 reclamationPeriod = 7 days;
    uint256 arbitrationFeeReclamationPeriod = 30 days;

    //Mappings
    mapping(uint256 => Reservation) public reservations;

    //Events
    event newReservation(uint256 reservationId, address host, address guest);

    //Structs and Enums
    struct Reservation {
        uint256 id;
        uint256 listing;
        uint startDate;
        uint duration;
        address host;
        address guest;
        uint256 charge;
        uint256 tx;
    }

    constructor(
        address _listingContract,
        address _aggregator,
        address _escrow
    ) {
        reservationCount = 0;
        listingContract = IListing(_listingContract);
        aggregator = AggregatorV3Interface(_aggregator); 
        escrow = Escrow(_escrow);
    }

    function reserve(
        uint256 _listingId,
        uint256 _startDate,
        uint256 _duration
    ) public payable {
        //Verify payment
        IListing.Listing memory listing = listingContract.getListing(
            _listingId
        );

        _duration = (_duration) / 1 days;

        uint256 reservationCharge = dollarsToWei(
            _duration * listing.price,
            getUSDPrice()
        );
        require(
            msg.value >= reservationCharge,
            "Not enough ETH to make reservation"
        );

        require(
            _startDate >= block.timestamp,
            "Start date must be in the future"
        );

        //Escrow Payment
        int256 _cancelationPeriod = int256(_startDate) -
            int256(block.timestamp) -
            int256(listing.cancelationPeriod);
        uint256 _tx = escrow.newTransaction{value: reservationCharge}({
            _payee: payable(listing.owner),
            _payer: payable(msg.sender),
            _reclamationPeriod: (_startDate + _duration) -
                block.timestamp +
                reclamationPeriod,
            _arbitrationFeeDepositPeriod: arbitrationFeeReclamationPeriod,
            _cancelationPeriod: _cancelationPeriod > 0
                ? uint256(_cancelationPeriod)
                : 0
        });

        //Save Reservation
        reservationCount++;
        reservations[reservationCount] = Reservation({
            id: reservationCount,
            listing: _listingId,
            startDate: _startDate,
            duration: _duration,
            host: listing.owner,
            guest: msg.sender,
            charge: reservationCharge,
            tx: _tx
        });
        emit newReservation(reservationCount, listing.owner, msg.sender);

        //Refund excess to sender
        payable(msg.sender).transfer(msg.value - reservationCharge);
    }

    function cancelReservation(uint256 _reservationId) public {
        Reservation memory reservation = reservations[_reservationId];
        uint256 cancelationPeriod = listingContract
            .getListing(reservation.listing)
            .cancelationPeriod;
        require(
            block.timestamp < reservation.startDate - cancelationPeriod,
            "Too late to cancel reservation."
        );

        escrow.cancelTransaction(reservation.tx, reservation.guest);

        delete reservations[_reservationId];
    }

    function getUSDPrice() private view returns (uint256) {
        (, int answer, , , ) = aggregator.latestRoundData();
        return uint256(answer * 10 ** 10);
    }

    function dollarsToWei(
        uint256 dollars,
        uint256 usdPrice
    ) private pure returns (uint256) {
        return (dollars * (10 ** 18) ** 2) / usdPrice;
    }
}
