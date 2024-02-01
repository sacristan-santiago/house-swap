from brownie import accounts, Reservations, Listings, SimpleCentralizedArbitrator, Escrow

def test_deploy():
    account = accounts[0]
    arbitrator = SimpleCentralizedArbitrator.deploy({"from": accounts[1]})
    escrow = Escrow.deploy(arbitrator, {"from": account})
    listing = Listings.deploy({"from": account})
    reservations = Reservations.deploy(listing, escrow, {"from": account})
    owner = reservations.owner()
    assert account == owner