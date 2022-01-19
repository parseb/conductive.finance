from brownie import accounts


def test_accountzero_isowner(yMarkt):
    assert yMarkt.owner() == accounts[0]
