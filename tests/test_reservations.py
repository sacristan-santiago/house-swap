
from brownie import accounts, network, Reservations, Listings, SimpleCentralizedArbitrator, Escrow, MockV3Aggregator
import brownie
import pytest
import time
from web3 import _utils


def test_deploy():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")

    reservations = deploy_reservations()

    assert accounts[0] == reservations.owner()


def test_reserve():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")
    
    reservations = deploy_reservations()

    tx2 = reservations.reserve(1, dateAdd(now(), 1), dayToSeconds(30), {"from": accounts[0], 'value': 10000000000000000000})
    tx2.wait(1)

    assert reservations.reservationCount() == 1


def test_not_enough_ETH_to_reserve():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")

    reservations = deploy_reservations()

    with brownie.reverts("Not enough ETH to make reservation"):
        reservations.reserve(1, dateAdd(now(), 1), dayToSeconds(30), {"from": accounts[0], 'value': 0})


def test_handle_float_duration():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")

    reservations = deploy_reservations()
    
    tx2 = reservations.reserve(1, dateAdd(now(), 1), dayToSeconds(1.5), {"from": accounts[0], 'value': 10000000000000000000})
    tx2.wait(1)

    assert reservations.reservations(1)[3] == 1 


def test_cancel_reservation():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")

    reservations = deploy_reservations()

    tx2 = reservations.reserve(1, dateAdd(now(), 10), dayToSeconds(30), {"from": accounts[0], 'value': 10000000000000000000})
    tx2.wait(1)

    assert reservations.reservations(1)[0] == 1

    tx3 = reservations.cancelReservation(1, {"from": accounts[0]})
    tx3.wait(1)

    assert reservations.reservations(1)[0] == 0


def test_too_late_to_cancel_reservation():
    if network.show_active() not in ["development"]:
        pytest.skip("only for development testing")

    reservations = deploy_reservations()

    tx2 = reservations.reserve(1, dateAdd(now(), 0), dayToSeconds(30), {"from": accounts[0], 'value': 10000000000000000000})
    tx2.wait(1)

    with brownie.reverts("Too late to cancel reservation."):  
        reservations.cancelReservation(1, {"from": accounts[0]})




def deploy_reservations():
    account = accounts[0]
    arbitrator = SimpleCentralizedArbitrator.deploy({"from": accounts[1]})
    escrow = Escrow.deploy(arbitrator, {"from": account})
    listing = Listings.deploy({"from": account})
    tx = listing.createListing(100, dayToSeconds(5), {"from": accounts[0]})
    tx.wait(1)
    aggregator = MockV3Aggregator.deploy(8, 2500*10**18, {"from": account})
    return Reservations.deploy(listing, aggregator, escrow, {"from": account})

def now() -> int:
    return int(time.time())

def dateAdd(initial: int, days: int) -> int:
    return now() + days*24*60*60

def dayToSeconds(days: int) -> int:
    return days*24*60*60
