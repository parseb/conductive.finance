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


def test_train_create_generates_valid_pool_registry(
    Conductive, solidSwap, YFI, wFTM, wFTMrich, TrainS, YFIrich
):
    p0 = solidSwap.getPair(YFI.address, wFTM.address, {"from": accounts[0]})
    wFTM.transfer(accounts[0], 400 * (10 ** 18), {"from": wFTMrich})
    YFI.transfer(accounts[0], 100 * (10 ** 18), {"from": YFIrich})
    wFTM.approve(Conductive.address, 4000 * (10 ** 18), {"from": accounts[0]})
    YFI.approve(Conductive.address, 400 * (10 ** 18), {"from": accounts[0]})
    if p0 == ZERO_ADDRESS:
        assert Conductive.createTrain(
            YFI.address,
            [1338, 3],
            2,
            [10 ** 18, 10 ** 18],
            [False, False],
            {"from": accounts[0]},
        )  # returns True
        p1 = solidSwap.getPair(YFI.address, wFTM.address, {"from": accounts[0]})
        assert p1 != p0
        p0 = p1
    else:
        assert Conductive.createTrain(
            YFI.address,
            [1338, 3],
            2,
            [10 ** 18, 10 ** 18],
            [False, False],
            {"from": accounts[0]},
        )

    assert p0 != ZERO_ADDRESS


def test_creating_train_with_existing_pool_fails(
    Conductive, solidSwap, YFIwFTM, YFI, wFTM, wFTMrich
):
    pair = solidSwap.getPair(YFI.address, wFTM.address, {"from": accounts[0]})
    assert pair != ZERO_ADDRESS

    assert Conductive.getTrain(pair, {"from": accounts[0]})[0][1] != ZERO_ADDRESS

    # wFTM.transfer(accounts[0].address, 10 * (10 ** 18), {"from": wFTMrich})
    # "Overriding train not allowed"
    with reverts("exists or no pool"):
        Conductive.createTrain(
            YFI.address,
            [1338, 51],
            2,
            [10 ** 18, 10 ** 18],
            [False, False],
            {"from": accounts[0]},
        )


def test_fails_on_per_price_too_low(Conductive, YFIwFTM, YFI, YFIrich, TrainS):
    YFI.transfer(accounts[1], 5000000000000000000, {"from": YFIrich})
    YFI.approve(TrainS.address, 5000000000000000000, {"from": accounts[1]})
    chain.mine(10)
    with reverts():
        Conductive.createTicket(
            1121,  # stations / cycles until vested
            2334,  # per unit / compensate at price
            YFIwFTM,  # pool / train address
            1,  #  nr of tokens / bag size
            {"from": accounts[1]},
        )


def test_create_ticket(Conductive, wFTM, YFI, YFIwFTM, YFIrich, TrainS):
    YFI.transfer(accounts[1], 2 * (10 ** 18), {"from": YFIrich})
    YFI.approve(TrainS.address, 999 * (10 ** 18), {"from": accounts[1]})
    chain.mine(10)
    train = Conductive.getTrain(YFIwFTM, {"from": accounts[0]})
    assert Conductive.createTicket(
        100,
        200 * (10 ** 18),
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[1]},
    )

    chain.mine(1)

    getTicket = Conductive.getTicket(accounts[1], YFIwFTM)
    getTicketById = Conductive.getTicketById(getTicket[-2])

    assert getTicket == getTicketById
    assert Conductive.ownerOf(getTicket[-2]) == accounts[1]
    assert getTicket[-3] == YFIwFTM
    assert chain.height == getTicket[1] + 1


def test_burns_ticket_strightforward(Conductive, TrainS, YFIwFTM, YFI):
    ticket = Conductive.getTicket(accounts[1], YFIwFTM)
    chain.mine(11)  # fails on less than 10
    prev_balance = YFI.balanceOf(accounts[1])
    prev_contract_balance = YFI.balanceOf(TrainS.address)

    assert Conductive.burnTicket(ticket[-2], {"from": accounts[1]})

    after_balance = YFI.balanceOf(accounts[1])
    after_contract_balance = YFI.balanceOf(TrainS.address)

    assert after_balance == prev_balance + ticket[2]
    assert after_contract_balance >= prev_contract_balance - ticket[2]

    with reverts():
        Conductive.ownerOf(ticket[-2])
    burned = Conductive.getTicket(accounts[1], YFIwFTM)
    assert burned[0] == burned[1] == burned[2] == burned[3] == burned[5] == 0
    chain.mine(6)


def test_burns_ticket_after_station_cycle(
    Conductive,
    TrainS,
    YFIwFTM,
    YFI,
    wFTM,
    solidRegistry,
    solidSwap,
    wFTMrich,
    YFIrich,
):
    assert Conductive.createTicket(
        100,
        230 * (10 ** 18),
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[1]},
    )

    # YFI.transfer(TrainS.address, 2 * (10 ** 18), {"from": YFIrich})
    wFTM.transfer(TrainS.address, 1 * (10 ** 18), {"from": wFTMrich})
    YFI.transfer(accounts[1], 2 * (10 ** 18), {"from": YFIrich})
    wFTM.transfer(accounts[1], 2 * (10 ** 18), {"from": wFTMrich})
    train = Conductive.getTrain(YFIwFTM, {"from": accounts[0]})
    nextStationAt = Conductive.nextStationAt(YFIwFTM)
    wFTM.approve(TrainS.address, 999999 * (10 ** 18), {"from": accounts[1]})

    with reverts("Train none or moving"):
        Conductive.trainStation(YFIwFTM, {"from": accounts[7]})

    chain.mine(nextStationAt - chain.height - 1)

    ## execute station cycle
    assert Conductive.trainStation(YFIwFTM, {"from": accounts[7]})

    ## cannot execute twice in same block
    with reverts():
        Conductive.trainStation(YFIwFTM, {"from": accounts[7]})
    chain.mine(1)

    ## not is station
    with reverts("Train none or moving"):
        Conductive.trainStation(YFIwFTM, {"from": accounts[7]})

    ## second station
    nextStationAt = Conductive.nextStationAt(YFIwFTM)
    chain.mine(nextStationAt - chain.height - 1)
    print("next station at:", nextStationAt, chain.height)

    assert Conductive.trainStation(YFIwFTM, {"from": accounts[7]})

    # ticket = Conductive.getTicket(accounts[1], YFIwFTM)
    # # burn ticket
    # assert Conductive.burnTicket(YFIwFTM, {"from": accounts[1]})


def test_assignsberner_burnerBurnes(Conductive, YFIwFTM, YFI, TrainS):
    ticket = Conductive.getTicket(accounts[1].address, YFIwFTM, {"from": accounts[1]})

    Conductive.burnTicket(ticket[-2], {"from": accounts[1]})
    chain.mine(10)
    assert Conductive.createTicket(
        100,
        230 * (10 ** 18),
        YFIwFTM,
        2 * (10 ** 18),
        {"from": accounts[1]},
    )

    chain.mine(22)
    ticket = Conductive.getTicket(accounts[1].address, YFIwFTM, {"from": accounts[1]})
    assert Conductive.assignBurner(
        ticket[-2],
        accounts[2].address,
        {"from": accounts[1]},
    )
    chain.mine(2)

    with reverts("active as collateral"):
        Conductive.requestOffBoarding(ticket[-3], {"from": accounts[1]})

    chain.mine(2)
    assert Conductive.burnTicket(ticket[-2], {"from": accounts[2]})


# def test_burns_ticket_after_offboard_request(Conductive, YFIwFTM, YFI):
#     pytest.skip("TODO")
