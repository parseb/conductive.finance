from brownie import accounts, ZERO_ADDRESS, interface


def test_contract_has_owner(Conductive):
    assert Conductive.owner() != ZERO_ADDRESS


def test_contract_has_been_deplyed_from_account8(Conductive):
    assert Conductive.owner() == accounts[8]
