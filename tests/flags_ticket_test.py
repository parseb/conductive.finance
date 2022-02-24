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
from tests.conftest import YFIrich, wFTMrich


def test_can_flag_ticket(Conductive, solidSwap, wFTM, YFI, YFIwFTM, YFIrich, TrainS):
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
