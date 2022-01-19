import pytest
from brownie import accounts, Ymarkt


@pytest.fixture(scope="module")
def yMarkt(Ymarkt, accounts):
    return accounts[0].deploy(Ymarkt)
