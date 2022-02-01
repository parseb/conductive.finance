from distutils.log import error
from sre_constants import ASSERT_NOT
import pytest
from brownie import (
    convert,
    ZERO_ADDRESS,
    accounts,
    chain,
    rpc,
    reverts,
    web3,
    Contract,
)
from brownie_tokens import MintableForkToken


def test_trainid_is_validatedbyby_uniswap_registry(yMarkt, uniswap):
    USDCWETH = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    USDC = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    WETH = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"
    unipool = str(uniswap.getPair(USDC, WETH))
    yresultunipool = str(yMarkt.isValidPool(USDC, WETH))
    assert yresultunipool == unipool
    ###  ValueError: invalid literal for int() with base 16: '' - ganache-cli:


def test_becomes_valid_pool(yMarkt, uniswap):
    STASIS = "0xdb25f211ab05b1c97d595516f45794528a807ad8"
    YFI = "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e"

    # assert yMarkt.isValidPool(STASIS, YFI, "3000") == ZERO_ADDRESS

    cycle_freq = 306  # blocks
    min_cycles = 100
    budget_slice = 2  # %2 distribute per cycle
    price_memory = 10  # 'days ago memory'
    minbag = 1

    assert yMarkt.createTrain(
        STASIS,
        YFI,
        [cycle_freq, min_cycles * cycle_freq, budget_slice, price_memory],
        minbag,
        True,
        True,
    )

    assert yMarkt.isValidPool(STASIS, YFI) != ZERO_ADDRESS

    ###  ValueError: invalid literal for int() with base 16: '' - ganache-cli:


def test_create_train_returns_true(yMarkt, addrzero, uniswap):
    cycle_freq = 306  # blocks
    min_cycles = 100
    budget_slice = 2  # %2 distribute per cycle
    price_memory = 10  # 'days ago memory'
    USDCWETH = "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8"
    USDC = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    WETH = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"
    minbag = 10
    # arguments: pool, yvault, cycelFreq, minDistance, budgetSlicer, upperRewardBound
    assert yMarkt.createTrain(
        USDC,
        WETH,
        [cycle_freq, min_cycles * cycle_freq, budget_slice, price_memory],
        minbag,
        True,
        True,
    )
    train_1 = yMarkt.getTrain(USDCWETH)
    assert yMarkt.isValidPool(USDC, WETH) != ZERO_ADDRESS
    assert accounts[0].address == yMarkt.owner()


def test_creates_ticket(yMarkt):
    USDC = "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
    WETH = "0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2"
    train = yMarkt.isValidPool(USDC, WETH)
    previous_number_of_passengers = yMarkt.getTrain(train)[4]
    price = 9001
    bagsize = 100
    previous_tickets_onprice = len(yMarkt.getTicketsByPrice(train, price))
    previous_inCustody = yMarkt.getTrain(train)[3]
    usdcrich = "0x2A549b4AF9Ec39B03142DA6dC32221fC390B5533"

    USDCtoken = MintableForkToken("0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
    USDCtoken.transfer(accounts[0], USDCtoken.balanceOf(usdcrich), {"from": usdcrich})

    chain.mine(2)
    USDCtoken.approve(
        yMarkt.address,
        USDCtoken.balanceOf(accounts[0]),
        {"from": accounts[0]},
    )
    chain.mine(1)
    assert yMarkt.getTrain(train)[-1][-1]

    ticket = yMarkt.createTicket(10000, price, train, 11)

    ##assert ticket
    assert yMarkt.getTrain(train)[4] == previous_number_of_passengers + 1
    assert len(yMarkt.getTicketsByPrice(train, price)) == previous_tickets_onprice + 1
    # assert yMarkt.getTrain(train)[3] == previous_inCustody + bagsize

    # errMsg = "0x65ba9ff1"
    ##errMsg = web3.keccak(text="MinDepositRequired()")[:4].hex()
    # with brownie.reverts(
    #     "typed error: 0x65ba9ff1000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000008"
    # ):
    #     x =yMarkt.createTicket(100, price, "0x8AD599C3A0FF1DE082011EFDDC58F1908EB6E6D8", 8)


def test_creates_train_with_vault(yMarkt):
    YFI = MintableForkToken("0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e")
    DAI = MintableForkToken("0x6B175474E89094C44Da98b954EedeAC495271d0F")
    YFIvault = "0xdb25ca703181e7484a155dd612b06f57e12be5f0"
    YFIrich = "0x34a4c5d747f54d5e3a3f66eb6ef3f697f474fd90"

    assert yMarkt.createTrain(
        YFI.address, DAI.address, [100, 20000, 30, 10], 9, True, True
    )


def test_creates_ticket_yvault(yMarkt):

    YFIrich = "0x34a4c5d747f54d5e3a3f66eb6ef3f697f474fd90"
    YFI = MintableForkToken("0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e")
    DAI = MintableForkToken("0x6B175474E89094C44Da98b954EedeAC495271d0F")
    # YFIvault = Contract.from_explorer("0xdb25ca703181e7484a155dd612b06f57e12be5f0")
    YFIvault = Contract("yfi_vault")
    pool_yfidai = yMarkt.isValidPool(YFI.address, DAI.address, {"from": accounts[0]})

    ##yfi_vault = Contract.from_abi("Vault", YFIvault, {"from": accounts[0]})

    assert pool_yfidai != ZERO_ADDRESS

    YFI.approve(accounts[0], YFI.balanceOf(YFIrich), {"from": YFIrich})
    chain.mine(1)
    YFI.transfer(accounts[0], YFI.balanceOf(YFIrich), {"from": YFIrich})
    chain.mine(10)

    YFI.approve(YFIvault.address, YFI.balanceOf(accounts[0]), {"from": accounts[0]})

    shares = YFIvault.deposit(10, {"from": accounts[0]})
    yToken = MintableForkToken(YFIvault.token())
    chain.mine(1)
    assert shares.return_value > 0

    assert YFIvault.token() == YFI.address
    ##YFI.approve(yMarkt.address, YFI.balanceOf(accounts[0]), {"from": accounts[0]})
    ##assert yMarkt.createTicket(100, 1000000, pool_yfidai, 14, {"from": accounts[0]})


def test_burns_ticket(yMarkt):
    YFI = MintableForkToken("0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e")
    DAI = MintableForkToken("0x6B175474E89094C44Da98b954EedeAC495271d0F")
    pool_yfidai = yMarkt.isValidPool(YFI.address, DAI.address, {"from": accounts[0]})

    YFI.transfer(accounts[3], 12345678910, {"from": accounts[0]})
    YFI.approve(yMarkt.address, 12345678910, {"from": accounts[3]})
    chain.mine(3)
    assert yMarkt.createTicket(
        10000,
        12334,
        pool_yfidai,
        31,
        {"from": accounts[3]},
    )

    chain.mine(1)

    train_prev = yMarkt.getTrain(pool_yfidai, {"from": accounts[0]})
    yMarkt.burnTicket(pool_yfidai, {"from": accounts[3]})
    train_after = yMarkt.getTrain(pool_yfidai, {"from": accounts[0]})

    assert train_prev[3] > train_after[3]
    assert train_prev[4] == train_after[4] + 1


########_later_########################################################################


def test_burns_vault_ticket(yMarkt):

    ## create ticket on trian with vault
    YFI = MintableForkToken("0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e")
    DAI = MintableForkToken("0x6B175474E89094C44Da98b954EedeAC495271d0F")
    YFIvault = Contract("yfi_vault")
    pool_yfidai = yMarkt.isValidPool(YFI.address, DAI.address, {"from": accounts[1]})
    assert pool_yfidai != ZERO_ADDRESS
    assert YFI.transfer(accounts[4], 100, {"from": accounts[0]})
    assert YFI.approve(yMarkt.address, 100, {"from": accounts[4]}).return_value
    quantity = 31
    ## deposit into vault
    prev_yfi_balance = YFI.balanceOf(accounts[4])
    assert yMarkt.createTicket(
        1,
        9000,
        pool_yfidai,
        quantity,
        {"from": accounts[4]},
    )

    chain.mine(1)
    ticket = yMarkt.getTicket(accounts[4].address, pool_yfidai, {"from": accounts[9]})
    ## burn ticket
    assert YFI.balanceOf(accounts[4].address) == prev_yfi_balance - quantity
    assert yMarkt.burnTicket(ticket[4], {"from": accounts[4]})
    assert YFI.balanceOf(accounts[4].address) == prev_yfi_balance

    ticket = yMarkt.getTicket(accounts[4].address, pool_yfidai, {"from": accounts[9]})
    assert ticket[0] == ZERO_ADDRESS
    assert ticket[1] == ZERO_ADDRESS
    assert ticket[2] == 0
    assert ticket[3] == 0
    assert ticket[4] == ZERO_ADDRESS


def checks_seating_functionality(yMarkt):
    return True
