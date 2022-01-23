import pytest
from brownie import convert, ZERO_ADDRESS, accounts, chain, rpc


def test_trainid_is_validatedbyby_uniswap_registry(yMarkt, uniswap):
    USDCWETH = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    USDC = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    WETH = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"
    unipool = str(uniswap.getPool(USDC, WETH, "3000"))
    yresultunipool = str(yMarkt.isValidPool(USDC, WETH, "3000"))
    assert yresultunipool == unipool
    ###  ValueError: invalid literal for int() with base 16: '' - ganache-cli:


def test_becomes_valid_pool(yMarkt, uniswap):
    STASIS = "0xdb25f211ab05b1c97d595516f45794528a807ad8"
    YFI = "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e"

    assert yMarkt.isValidPool(STASIS, YFI, "3000") == ZERO_ADDRESS

    cycle_freq = 306  # blocks
    min_cycles = 100
    budget_slice = 2  # %2 distribute per cycle
    price_memory = 10  # 'days ago memory'

    assert yMarkt.createTrain(
        STASIS,
        YFI,
        3000,
        ZERO_ADDRESS,
        cycle_freq,
        min_cycles * cycle_freq,
        budget_slice,
        price_memory,
    )

    assert yMarkt.isValidPool(STASIS, YFI, "3000") != ZERO_ADDRESS

    ###  ValueError: invalid literal for int() with base 16: '' - ganache-cli:


def test_create_train_returns_true(yMarkt, addrzero, uniswap):
    cycle_freq = 306  # blocks
    min_cycles = 100
    budget_slice = 2  # %2 distribute per cycle
    price_memory = 10  # 'days ago memory'
    USDCWETH = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    USDC = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    WETH = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"

    # arguments: pool, yvault, cycelFreq, minDistance, budgetSlicer, upperRewardBound
    assert yMarkt.createTrain(
        USDC,
        WETH,
        3000,
        addrzero,
        cycle_freq,
        min_cycles * cycle_freq,
        budget_slice,
        price_memory,
    )


def test_creates_ticket(yMarkt):
    train = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    previous_number_of_passengers = yMarkt.getTrain(train)[2]
    price = 9001
    previous_tickets_onprice = len(yMarkt.getTicketsByPrice(train, price))

    ticket = yMarkt.createTicket(
        10000, 100, price, "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    )
    chain.mine(2)
    assert ticket
    assert yMarkt.getTrain(train)[2] == previous_number_of_passengers + 1
    assert len(yMarkt.getTicketsByPrice(train, price)) == previous_tickets_onprice + 1
