from brownie import accounts, ZERO_ADDRESS, interface


def test_contract_has_owner(yMarkt):
    assert yMarkt.owner() != ZERO_ADDRESS


def test_contract_has_been_deplyed_from_account0(yMarkt):
    assert yMarkt.owner() == accounts[0]
