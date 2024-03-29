// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import {IArbitrable} from "@kleros/erc-792/contracts/IArbitrable.sol";
import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";
import {IEvidence} from "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";

contract Escrow is IArbitrable, IEvidence {
    enum Status {
        Initial,
        Reclaimed,
        Disputed,
        Resolved,
        Canceled
    }
    enum RulingOptions {
        RefusedToArbitrate,
        PayerWins,
        PayeeWins
    }
    uint256 constant numberOfRulingOptions = 2;

    error InvalidStatus();
    error ReleasedTooEarly();
    error NotPayer();
    error NotPayerNorPayee();
    error NotArbitrator();
    error ThirdPartyNotAllowed();
    error PayeeDepositStillPending();
    error ReclaimedTooLate();
    error CanceledTooLate();
    error InsufficientPayment(uint256 _available, uint256 _required);
    error InvalidRuling(uint256 _ruling, uint256 _numberOfChoices);

    struct TX {
        address payable payer;
        address payable payee;
        Status status;
        uint256 value;
        uint256 disputeID;
        uint256 createdAt;
        uint256 reclaimedAt;
        uint256 payerFeeDeposit;
        uint256 payeeFeeDeposit;
        uint256 reclamationPeriod;
        uint256 arbitrationFeeDepositPeriod;
        uint256 cancelationPeriod;
    }

    TX[] public txs;
    IArbitrator arbitrator;
    mapping(uint256 => uint256) disputeIDtoTXID;

    constructor(address _arbitrator) {
        arbitrator = IArbitrator(_arbitrator);
    }

    function newTransaction(
        address payable _payee,
        address payable _payer,
        uint256 _reclamationPeriod,
        uint256 _arbitrationFeeDepositPeriod,
        uint256 _cancelationPeriod
    ) public payable returns (uint256) {
        txs.push(
            TX({
                payer: _payer,
                payee: _payee,
                status: Status.Initial,
                value: msg.value,
                disputeID: 0,
                createdAt: block.timestamp,
                reclaimedAt: 0,
                payerFeeDeposit: 0,
                payeeFeeDeposit: 0,
                reclamationPeriod: _reclamationPeriod,
                arbitrationFeeDepositPeriod: _arbitrationFeeDepositPeriod,
                cancelationPeriod: _cancelationPeriod
            })
        );

        return txs.length - 1;
    }

    function releaseFunds(uint256 _txID) public {
        TX storage transaction = txs[_txID];

        if (transaction.status != Status.Initial) {
            revert InvalidStatus();
        }
        if (
            block.timestamp - transaction.createdAt <=
            transaction.reclamationPeriod
        ) {
            revert ReleasedTooEarly();
        }

        transaction.status = Status.Resolved;
        transaction.payee.transfer(transaction.value);
    }

    function cancelTransaction(uint256 _txID, address caller) public {
        TX storage transaction = txs[_txID];

        if (transaction.status != Status.Initial) {
            revert InvalidStatus();
        }
        if (caller != transaction.payer || caller != transaction.payee) {
            revert NotPayerNorPayee();
        }
        if (
            block.timestamp - transaction.createdAt >
            transaction.cancelationPeriod
        ) {
            revert CanceledTooLate();
        }

        transaction.payer.transfer(transaction.value);
        transaction.status = Status.Canceled;
    }

    function reclaimFunds(uint256 _txID) public payable {
        TX storage transaction = txs[_txID];

        if (
            transaction.status != Status.Initial &&
            transaction.status != Status.Reclaimed
        ) {
            revert InvalidStatus();
        }
        if (msg.sender != transaction.payer) {
            revert NotPayer();
        }

        if (transaction.status == Status.Reclaimed) {
            if (
                block.timestamp - transaction.reclaimedAt <=
                transaction.arbitrationFeeDepositPeriod
            ) {
                revert PayeeDepositStillPending();
            }
            transaction.payer.transfer(
                transaction.value + transaction.payerFeeDeposit
            );
            transaction.status = Status.Resolved;
        } else {
            if (
                block.timestamp - transaction.createdAt >
                transaction.reclamationPeriod
            ) {
                revert ReclaimedTooLate();
            }

            uint256 requiredAmount = arbitrator.arbitrationCost("");
            if (msg.value < requiredAmount) {
                revert InsufficientPayment(msg.value, requiredAmount);
            }

            transaction.payerFeeDeposit = msg.value;
            transaction.reclaimedAt = block.timestamp;
            transaction.status = Status.Reclaimed;
        }
    }

    function depositArbitrationFeeForPayee(uint256 _txID) public payable {
        TX storage transaction = txs[_txID];

        if (transaction.status != Status.Reclaimed) {
            revert InvalidStatus();
        }

        transaction.payeeFeeDeposit = msg.value;
        transaction.disputeID = arbitrator.createDispute{value: msg.value}(
            numberOfRulingOptions,
            ""
        );
        transaction.status = Status.Disputed;
        disputeIDtoTXID[transaction.disputeID] = _txID;
        emit Dispute(arbitrator, transaction.disputeID, _txID, _txID);
    }

    function rule(uint256 _disputeID, uint256 _ruling) public override {
        uint256 txID = disputeIDtoTXID[_disputeID];
        TX storage transaction = txs[txID];

        if (msg.sender != address(arbitrator)) {
            revert NotArbitrator();
        }
        if (transaction.status != Status.Disputed) {
            revert InvalidStatus();
        }
        if (_ruling > numberOfRulingOptions) {
            revert InvalidRuling(_ruling, numberOfRulingOptions);
        }
        transaction.status = Status.Resolved;

        if (_ruling == uint256(RulingOptions.PayerWins))
            transaction.payer.transfer(
                transaction.value + transaction.payerFeeDeposit
            );
        else
            transaction.payee.transfer(
                transaction.value + transaction.payeeFeeDeposit
            );
        emit Ruling(arbitrator, _disputeID, _ruling);
    }

    function submitEvidence(uint256 _txID, string memory _evidence) public {
        TX storage transaction = txs[_txID];

        if (transaction.status == Status.Resolved) {
            revert InvalidStatus();
        }

        if (
            msg.sender != transaction.payer && msg.sender != transaction.payee
        ) {
            revert ThirdPartyNotAllowed();
        }
        emit Evidence(arbitrator, _txID, msg.sender, _evidence);
    }

    function remainingTimeToReclaim(
        uint256 _txID
    ) public view returns (uint256) {
        TX storage transaction = txs[_txID];

        if (transaction.status != Status.Initial) {
            revert InvalidStatus();
        }
        return
            (block.timestamp - transaction.createdAt) >
                transaction.reclamationPeriod
                ? 0
                : (transaction.createdAt +
                    transaction.reclamationPeriod -
                    block.timestamp);
    }

    function remainingTimeToDepositArbitrationFee(
        uint256 _txID
    ) public view returns (uint256) {
        TX storage transaction = txs[_txID];

        if (transaction.status != Status.Reclaimed) {
            revert InvalidStatus();
        }
        return
            (block.timestamp - transaction.reclaimedAt) >
                transaction.arbitrationFeeDepositPeriod
                ? 0
                : (transaction.reclaimedAt +
                    transaction.arbitrationFeeDepositPeriod -
                    block.timestamp);
    }

    function getTransaction(uint256 _TX) public view returns (TX memory) {
        return txs[_TX];
    }
}
