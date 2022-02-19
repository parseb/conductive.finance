import pytest
from brownie import (
    accounts,
    ValueConduct,
    Conductive,
    TrainSpotting,
    Contract,
    chain,
    convert,
    rpc,
)
from brownie_tokens import MintableForkToken
import time


@pytest.fixture(scope="module")
def VC(accounts):
    vc = accounts[8].deploy(ValueConduct)
    vc.transfer(
        accounts[0], vc.balanceOf(accounts[8].address) / 100, {"from": accounts[8]}
    )
    return vc


@pytest.fixture(scope="module")
def TrainS(TrainSpotting, accounts, VC):
    ts = accounts[8].deploy(
        TrainSpotting,
        VC.address,
        "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
    )
    VC.transfer(ts.address, VC.balanceOf(accounts[8]), {"from": accounts[8]})
    VC.renounceOwnership({"from": accounts[8]})
    return ts


@pytest.fixture(scope="module")
def Conductive(Conductive, TrainS, accounts):
    return accounts[8].deploy(
        Conductive, "0xc35DADB65012eC5796536bD9864eD8773aBc74C4", TrainS.address
    )


# def load_contract(addr):
#     try:
#         cont = Contract(addr)
#     except:
#         cont = Contract.from_explorer(addr)
#     return cont


@pytest.fixture(scope="module")
def solidSwap():
    univ2 = Contract.from_explorer("0xc35DADB65012eC5796536bD9864eD8773aBc74C4")
    univ2.set_alias("pairF")
    time.sleep(1)
    yield univ2


@pytest.fixture(scope="module")
def solidRegistry():
    univ2 = Contract.from_explorer("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506")
    univ2.set_alias("swapRegistry")
    yield univ2


@pytest.fixture(scope="module")
def YFI():
    YFI = MintableForkToken("0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683")
    time.sleep(1)
    return YFI


@pytest.fixture(scope="module")
def YFIrich():
    return accounts[-2]
    # ftm unlock: ["0xc0f112479c83a603ac4dc76f616536389a85a917", "0x6398acbbab2561553a9e458ab67dcfbd58944e52"]
    # poly SAND DAI unlock:["0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683","0x27F8D03b3a2196956ED754baDc28D73be8830A6e"]


@pytest.fixture(scope="module")
def wFTM(Conductive, VC):
    # wftm = MintableForkToken("0x8f3cf7ad23cd3cadbd9735aff958023239c6a063")
    return VC


@pytest.fixture(scope="module")
def wFTMrich(wFTM):
    # wFTM.transfer(accounts[0], 1000 * (10 ** 18), {"from": accounts[-1]})
    return accounts[0]


@pytest.fixture(scope="module")
def addrzero():
    return "0x0000000000000000000000000000000000000000"


@pytest.fixture(scope="module")
def YFIwFTM(wFTM, YFI, solidSwap):
    pair = solidSwap.getPair(YFI.address, wFTM.address, {"from": accounts[0]})
    if pair == "0x0000000000000000000000000000000000000000":
        pair = solidSwap.createPair(YFI.address, wFTM.address, {"from": accounts[0]})
    return pair


# @pytest.fixture(scope="module")
# def lPair(YFIwFTM):
#     pair = Contract.from_explorer(YFIwFTM)
#     pair.set_alias("lPair")
#     yield pair
