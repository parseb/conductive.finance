import pytest
from brownie import accounts, Ymarkt, Contract, chain


@pytest.fixture(scope="module")
def yMarkt(Ymarkt, accounts):
    return accounts[0].deploy(Ymarkt)


# def load_contract(addr):
#     try:
#         cont = Contract(addr)
#     except:
#         cont = Contract.from_explorer(addr)
#     return cont


# @pytest.fixture(scope="module")
# def uniswapV3Factory():
#     return load_contract("0x1F98431c8aD98523631AE4a59f267346ea31F984")
