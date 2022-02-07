import pytest
from brownie import accounts, Conductive, Contract, chain, convert, rpc
from brownie_tokens import MintableForkToken


@pytest.fixture(scope="module")
def Conductive(Conductive, accounts):
    return accounts[0].deploy(
        Conductive,
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
    YFI.set_alias("yfi")
    return YFI


@pytest.fixture(scope="module")
def YFIrich():
    return accounts[-2]
    # unlock: ["0xc0f112479c83a603ac4dc76f616536389a85a917", "0x6398acbbab2561553a9e458ab67dcfbd58944e52"]


@pytest.fixture(scope="module")
def wFTM():
    wftm = MintableForkToken("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
    wftm.set_alias("wftm")
    return wftm


@pytest.fixture(scope="module")
def wFTMrich():
    return accounts[-1]


@pytest.fixture(scope="module")
def addrzero():
    return "0x0000000000000000000000000000000000000000"


@pytest.fixture(scope="module")
def YFIwFTM(wFTM, YFI, solidSwap):
    pair = solidSwap.getPair(YFI.address, wFTM.address, False, {"from": accounts[0]})
    if pair == "0x0000000000000000000000000000000000000000":
        pair = solidSwap.createPair(
            YFI.address, wFTM.address, False, {"from": accounts[0]}
        )
    return pair


@pytest.fixture(scope="module")
def YFIwFTM(wFTM, YFI, solidSwap):
    pair = solidSwap.getPair(YFI.address, wFTM.address, False, {"from": accounts[0]})
    if pair == "0x0000000000000000000000000000000000000000":
        pair = solidSwap.createPair(
            YFI.address, wFTM.address, False, {"from": accounts[0]}
        )
    return pair
