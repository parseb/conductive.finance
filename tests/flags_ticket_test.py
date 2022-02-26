from distutils.log import error
from math import fabs
from sre_constants import ASSERT_NOT
from uuid import RESERVED_MICROSOFT
import pytest
from brownie import (
    accounts,
    chain,
    ZERO_ADDRESS,
    Contract,
    convert,
    rpc,
    Conductive,
    reverts,
)

from brownie_tokens import MintableForkToken
from tests.conftest import YFIrich, solidRegistry, wFTMrich


def test_can_flag_ticket(
    Conductive, solidSwap, solidRegistry, wFTM, YFI, YFIwFTM, YFIrich, TrainS
):
    # wFTM.transfer(accounts[0], 400 * (10 ** 18), {"from": wFTMrich})
    YFI.transfer(accounts[0], 800 * (10 ** 18), {"from": YFIrich})

    wFTM.approve(Conductive.address, 4000 * (10 ** 18), {"from": accounts[0]})
    YFI.approve(Conductive.address, 400 * (10 ** 18), {"from": accounts[0]})
    YFI.approve(TrainS.address, 400 * (10 ** 18), {"from": accounts[0]})

    assert Conductive.createTrain(
        YFI.address,
        [1338, 3],
        2,
        [10 ** 18, 10 ** 18],
        [0, 0],
        [False, False],
        {"from": accounts[0]},
    )  # returns True

    assert Conductive.createTicket(
        100,
        69,
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[0]},
    )

    ticket = Conductive.getTicket(accounts[0].address, YFIwFTM)
    assert ticket[-2] > 0

    chain.mine(1000)

    with reverts("Invalid TWPrice"):
        Conductive.flagTicket(ticket[-2], 70, {"from": accounts[6]})

    wFTM.approve(solidRegistry.address, 1234567891234567890000, {"from": accounts[0]})
    YFI.approve(solidRegistry.address, 1234567891234567890000, {"from": accounts[0]})

    solidRegistry.addLiquidity(
        YFI.address,
        wFTM.address,
        123456789123456789000,
        123456789123456789000,
        0,
        0,
        accounts[0].address,
        chain.time() + 10,
        {"from": accounts[0]},
    )

    chain.mine()

    swaps = solidRegistry.swapExactTokensForTokens(
        12345678912345678,
        0,
        [wFTM.address, YFI.address],
        accounts[0].address,
        chain.time() + 10,
        {"from": accounts[0]},
    )

    assert swaps.return_value[0] > 1

    assert Conductive.flagTicket(ticket[-2], 70, {"from": accounts[6]})
