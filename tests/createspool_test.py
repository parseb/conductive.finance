from brownie import accounts, ZERO_ADDRESS, interface


def test_contract_has_owner(yMarkt):
    assert yMarkt.owner() != ZERO_ADDRESS


def test_contract_has_been_deplyed_from_account0(yMarkt):
    assert yMarkt.owner() == accounts[0]


# def test_pool_is_validated_by_uniswap_registry(yMarkt, uniswapV3Factory):

#     pooladdress = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
#     usdc = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
#     weth = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"
#     assert yMarkt.isValidPool(usdc, weth)
