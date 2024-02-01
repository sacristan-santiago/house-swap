// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import {IListing} from "../interfaces/IListing.sol";
import {Escrow} from "./Escrow.sol";
import {IArbitrable} from "../interfaces/IArbitrable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Reservations {
    //Variables
    address public owner = msg.sender;
    IListing internal listingContract;
    AggregatorV3Interface internal dataFeed;
    Escrow escrow;
    uint256 internal ReservationCount;
    uint256 reclamationPeriod = 7 days;
    uint256 arbitrationFeeReclamationPeriod = 30 days;
    uint256 cancelationPeriod = 7 days;

    //Mappings
    mapping(address => uint256[]) public hostReservations;
    mapping(address => uint256[]) public guestReservations;
    mapping(uint256 => Reservation) public reservations;

    //Events
    event newReservation(uint256 reservationId, address host, address guest);

    //Structs and Enums
    struct Reservation {
        uint256 id;
        uint256 listing;
        uint startDate;
        uint endDate;
        address host;
        address guest;
        uint256 charge;
        uint256 tx;
    }
    enum Status {
        Open,
        Closed
    }

    constructor(address _listingContract, address _escrow) {
        ReservationCount = 0;
        listingContract = IListing(_listingContract); // Initialize the instance with the Listing contract address
        dataFeed = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        ); //ZEPOLIA TESTNET
        escrow = Escrow(_escrow);
    }

    function reserve(
        uint256 _listingId,
        uint256 _startDate,
        uint256 _endDate
    ) public payable {
        //Verify payment
        IListing.Listing memory listing = listingContract.getListing(
            _listingId
        );
        uint256 reservationCharge = dollarsToWei(
            ((_endDate - _startDate) / 60 / 60 / 24) * listing.price,
            getUSDPrice()
        );
        require(
            msg.value >= reservationCharge,
            "Not enough ETH to make reservation"
        );

        //Escrow Payment
        uint256 _tx = escrow.newTransaction{value: reservationCharge}({
            _payee: payable(listing.owner),
            _payer: payable(msg.sender),
            _reclamationPeriod: block.timestamp - _endDate + reclamationPeriod,
            _arbitrationFeeDepositPeriod: arbitrationFeeReclamationPeriod,
            _cancelationPeriod: _startDate - block.timestamp - reclamationPeriod
        });

        //Save Reservation
        ReservationCount++;
        guestReservations[msg.sender].push(ReservationCount);
        hostReservations[listing.owner].push(ReservationCount);
        reservations[ReservationCount] = Reservation({
            id: ReservationCount,
            listing: _listingId,
            startDate: _startDate,
            endDate: _endDate,
            host: listing.owner,
            guest: msg.sender,
            charge: reservationCharge,
            tx: _tx
        });
        emit newReservation(ReservationCount, listing.owner, msg.sender);

        //Refund excess to sender
        payable(msg.sender).transfer(msg.value - reservationCharge);
    }

    function cancelReservation(uint256 _reservationId) public {
        Reservation memory reservation = reservations[_reservationId];
        require(
            reservation.startDate - cancelationPeriod < block.timestamp,
            "Cannot cancel a reservation after start date"
        );

        escrow.cancelTransaction(reservation.tx, reservation.guest);

        //Delete host reservation
        uint256[] memory _hostReservations = hostReservations[reservation.host];
        for (uint256 i = 0; i < _hostReservations.length; i++) {
            if (_hostReservations[i] == _reservationId) {
                hostReservations[reservation.host][i] = hostReservations[
                    reservation.host
                ][_hostReservations.length - 1];
                hostReservations[reservation.host].pop();
                break;
            }
        }

        //Delete guest reservation
        uint256[] memory _gestReservations = guestReservations[
            reservation.host
        ];
        for (uint256 i = 0; i < _gestReservations.length; i++) {
            if (_gestReservations[i] == _reservationId) {
                guestReservations[reservation.guest][i] = guestReservations[
                    reservation.guest
                ][_gestReservations.length - 1];
                guestReservations[reservation.guest].pop();
                break;
            }
        }

        delete reservations[_reservationId];
    }

    function getUSDPrice() private pure returns (uint256) {
        //(,int answer,,,) = dataFeed.latestRoundData();
        //return uint256(answer * 10**10); // USD/ETH * 10**18
        return 2500 * 10 ** 18;
    }

    function dollarsToWei(
        uint256 dollars,
        uint256 usdPrice
    ) private pure returns (uint256) {
        return (dollars * (10 ** 18) ** 2) / usdPrice;
    }
}
