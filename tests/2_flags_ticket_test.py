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
        3,
        69,
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[0]},
    )

    chain.mine(1)

    YFI.transfer(accounts[1].address, 123456789123456789000, {"from": accounts[0]})
    # YFI.approve(Conductive.address, 1234567891234567890000, {"from": accounts[1]})
    YFI.approve(TrainS.address, 400 * (10 ** 18), {"from": accounts[1]})

    assert Conductive.createTicket(
        3,
        69,
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[1]},
    )

    ticket1 = Conductive.getTicket(accounts[0].address, YFIwFTM)
    assert ticket1[-2] > 0

    with reverts("Invalid TWPrice"):
        Conductive.flagTicket(ticket1[-2], 70, {"from": accounts[6]})

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

    chain.mine(1)

    swaps = solidRegistry.swapExactTokensForTokens(
        12345678912345678,
        0,
        [wFTM.address, YFI.address],
        accounts[0].address,
        chain.time() + 10,
        {"from": accounts[0]},
    )
    assert swaps.return_value[0] > 1

    chain.mine(1)
    inCustody = Conductive.getTrain(YFIwFTM)[2]

    ticket2 = Conductive.getTicket(accounts[1].address, YFIwFTM)
    inCustody = Conductive.getTrain(YFIwFTM)[2]
    assert inCustody == (ticket1[2] + ticket2[2])
    assert ticket2[-2] > ticket1[-2]

    # flags ticket 1
    assert Conductive.flagTicket(ticket1[-2], 70, {"from": accounts[6]})
    chain.mine(1)

    with reverts("maybe not next station"):
        Conductive.requestOffBoarding(YFIwFTM, {"from": accounts[1]})

    balanceYFI0 = YFI.balanceOf(TrainS.address)

    # req offboard ticket2
    nextAt = Conductive.nextStationAt(YFIwFTM)
    chain.mine(ticket2[0] - chain.height)  # ~1 station
    Conductive.requestOffBoarding(YFIwFTM, {"from": accounts[1]})

    flagged1 = Conductive.getFlaggedQueue(YFIwFTM)
    offboarding1 = Conductive.getOffboardingQueue(YFIwFTM)

    nextAt = Conductive.nextStationAt(YFIwFTM)
    chain.mine(nextAt - chain.height - 1)
    sLeft = Conductive.stationsLeft(ticket2[-2])

    ### Train Station

    assert Conductive.trainStation(YFIwFTM)

    balanceYFI1 = YFI.balanceOf(TrainS.address)
    flagged2 = Conductive.getFlaggedQueue(YFIwFTM)
    offboarding2 = Conductive.getOffboardingQueue(YFIwFTM)
    assert len(flagged1) > len(flagged2)
    assert len(offboarding1) > len(offboarding2)
    assert len(flagged2) == len(offboarding2) == 0


###copied


def test_adds_to_offboard_request(Conductive, YFIwFTM, YFI, TrainS, wFTM):

    train = Conductive.getTrain(YFIwFTM, {"from": accounts[0]})

    assert Conductive.createTicket(
        100,
        230 * (10 ** 18),
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[1]},
    )

    ticket = Conductive.getTicket(accounts[1].address, YFIwFTM, {"from": accounts[1]})
    nextStationAt = Conductive.nextStationAt(YFIwFTM)
    chain.mine(10)
    assert Conductive.stationsLeft(ticket[-2]) >= 1

    with reverts():
        Conductive.requestOffBoarding(ticket[-3], {"from": accounts[1]})

    stationLeft = Conductive.nextStationAt(ticket[-3])
    chain.mine(ticket[0] - chain.height)
    assert Conductive.stationsLeft(ticket[-2]) <= 1
    chain
    assert Conductive.requestOffBoarding(ticket[-3], {"from": accounts[1]})

    afterRequest = Conductive.getOffboardingQueue(ticket[-2], 0, {"from": accounts[8]})

    assert afterRequest.len() >= 1

    with reverts():
        Conductive.requestOffBoarding(ticket[-3], {"from": accounts[1]})

    with reverts():
        Conductive.burnTicket(ticket[-2], {"from": accounts[1]})
