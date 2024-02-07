from brownie import accounts, config, interface, network
import pytest

def test_deploy_pool():
    if network.show_active() not in ["mainnet-fork"]:
        pytest.skip("only for forked testing")
    poolAddresssProvider = interface.IPoolAddressesProvider(config["networks"][network.show_active()]["pool-addresses-provider"])
    poolAddress = poolAddresssProvider.getPool() 
    pool = interface.IPool(poolAddress)

    assert pool is not None


def test_lend_ETH():
    if network.show_active() not in ["mainnet-fork"]:
        pytest.skip("only for forked testing")
    wethAddress = config["networks"][network.show_active()]["weth-token"]
    weth = interface.IWETH9(wethAddress)

    pool = get_pool()

    print("Despositing WETH...")
    wethDeposit = 0.1*10**18
    tx1 = weth.deposit({"from": accounts[0], "value": wethDeposit})
    tx1.wait(1)

    print("0.1 WETH desposited!")

    print("Approving WETH usage by pool..")
    tx2 = weth.approve(pool.address, wethDeposit, {"from": accounts[0]})
    tx2.wait(1)
    print("WETH usage approved!")

    print("Supplying WETH to pool...")
    tx3 = pool.supply(
        wethAddress,
        wethDeposit,
        accounts[0],
        0,
        {"from": accounts[0]}
    )
    tx3.wait(1)
    print("WETH supplied!")

    print("Withdrawing WETH + interests...")
    max = 2**256 - 1
    tx4 = pool.withdraw(wethAddress, max, accounts[0], {"from": accounts[0]})
    tx4.wait(1)
    print("WETH withdrawn!")

    wethWithdrawal = weth.balanceOf(accounts[0])
    print("Total WETH after lending: ")
    print(wethWithdrawal)

    assert wethWithdrawal > wethDeposit


def get_pool():
    poolAddresssProvider = interface.IPoolAddressesProvider(config["networks"][network.show_active()]["pool-addresses-provider"])
    poolAddress = poolAddresssProvider.getPool() 
    return interface.IPool(poolAddress)
