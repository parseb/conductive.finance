import pytest
from brownie import accounts, Ymarkt, Contract, chain, convert, rpc


@pytest.fixture(scope="module")
def yMarkt(Ymarkt, accounts):
    return accounts[0].deploy(Ymarkt)


# def load_contract(addr):
#     try:
#         cont = Contract(addr)
#     except:
#         cont = Contract.from_explorer(addr)
#     return cont


@pytest.fixture(scope="module")
def uniswap():
    univ2 = Contract.from_explorer("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f")
    # univ2.set_alias("uniswap")
    yield univ2


@pytest.fixture(scope="module")
def addrzero():
    return "0x0000000000000000000000000000000000000000"
