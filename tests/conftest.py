import pytest
from brownie import accounts, Ymarkt, Contract, chain, convert, rpc
from brownie_tokens import MintableForkToken


@pytest.fixture(scope="module")
def yMarkt(Ymarkt, accounts):
    return accounts[0].deploy(
        Ymarkt,
        "0x117F6F61e797E411Ea92F0ea1555c397Ecf17939",
        "0xCAE00F31F7cB5A78450Ca119fc2D0e7bbaEF0439",
    )


# def load_contract(addr):
#     try:
#         cont = Contract(addr)
#     except:
#         cont = Contract.from_explorer(addr)
#     return cont


@pytest.fixture(scope="module")
def solidSwap():
    univ2 = Contract.from_explorer("0x117F6F61e797E411Ea92F0ea1555c397Ecf17939")
    # univ2.set_alias("uniswap")
    yield univ2


@pytest.fixture(scope="module")
def solidRegistry():
    univ2 = Contract.from_explorer("0xCAE00F31F7cB5A78450Ca119fc2D0e7bbaEF0439")
    # univ2.set_alias("uniswap")
    yield univ2


@pytest.fixture(scope="module")
def YFI():
    YFI = MintableForkToken("0x29b0Da86e484E1C0029B56e817912d778aC0EC69")
    return YFI


@pytest.fixture(scope="module")
def wFTM():
    wftm = MintableForkToken("0x27Ce41c3cb9AdB5Edb2d8bE253A1c6A64Db8c96d")
    return wftm


@pytest.fixture(scope="module")
def addrzero():
    return "0x0000000000000000000000000000000000000000"
