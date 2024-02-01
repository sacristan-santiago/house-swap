from brownie import accounts, Reservations

def deploy():
    account = accounts[0]
    reservations = Reservations.deploy({"from": account})
    r

def main():
    deploy()