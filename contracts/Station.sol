//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "./UniswapInterfaces.sol";

contract TrainSpotting is ReentrancyGuard {
    struct stationData {
        uint256 at;
        uint256 price;
        uint256 ownedQty;
        uint256 lastGas;
    }

    struct operators {
        address buybackToken; //buyback token contract address
        address uniPool; //address of the uniswap pool ^
    }

    struct configdata {
        uint64[4] cycleParams; // [cycleFreq, minDistance, budgetSlicer, perDecimalDepth]
        uint256 minBagSize; // min bag size
        bool controlledSpeed; // if true, facilitate speed management
    }

    struct Train {
        operators meta;
        uint256 yieldSharesTotal; //increments on cycle, decrements on offboard
        uint256 budget; //total disposable budget
        uint256 inCustody; //total bag volume
        uint64 passengers; //unique participants/positions
        configdata config; //configdata
    }

    struct Ticket {
        uint128 destination; //promises to travel to block
        uint128 departure; // created on block
        uint256 bagSize; //amount token
        uint256 perUnit; //buyout price
        address trainAddress; //train ID (pair pool)
        uint256 nftid; //nft id
    }

    mapping(address => stationData) public lastStation;

    address immutable globalToken;
    address immutable mainStation;
    IUniswapV2Router02 solidRouter;

    constructor(
        address _globalToken,
        address _mainStation,
        address _router
    ) public {
        globalToken = _globalToken;
        mainStation = _mainStation;
        solidRouter = IUniswapV2Router02(_router);
    }

    event TrainInStation(address indexed _trainAddress, uint256 _nrstation);
    event TrainStarted(address indexed _trainAddress, stationData _station);
    event TrainConductorWithdrawal(
        address buybackToken,
        address trainAddress,
        uint256 quantity
    );

    function _trainStation(
        Train memory _train,
        uint256 _price,
        uint256 _g1
    ) internal nonReentrant returns (bool) {
        require(msg.sender == mainStation);

        ///////////////////////////////////////////
        ////////  first departure
        address _trainAddress = _train.meta.uniPool;

        if (lastStation[_trainAddress].lastGas == 0) {
            lastStation[_trainAddress].price =
                _price /
                (10**(18 - _train.config.cycleParams[3]));
            lastStation[_trainAddress].ownedQty = IERC20(
                _train.meta.buybackToken
            ).balanceOf(mainStation);

            lastStation[_trainAddress].lastGas = _g1 - gasleft();
            return true;
        }

        ////////////////////////////////////////////////////////////////////
        uint256 remaining = IERC20(_train.meta.buybackToken).balanceOf(
            mainStation
        );

        uint256 card = _train.budget;
        uint64 percentage = _train.config.cycleParams[2];
        if (_train.budget > 0)
            _train.budget =
                _train.budget -
                ((percentage * _train.budget) / 100);

        card = card - _train.budget;
        uint256 price2 = IUniswapV2Pair(_train.meta.uniPool)
            .price0CumulativeLast();
        card = card / price2;
        lastStation[_trainAddress].ownedQty += card;

        /// ^ ? wut
        /// add liquidity. buyback using slice of budget

        solidRouter.addLiquidity(
            _train.meta.buybackToken,
            globalToken,
            IERC20(_train.meta.buybackToken).balanceOf(address(this)),
            IERC20(globalToken).balanceOf(address(this)),
            0,
            0,
            mainStation,
            block.timestamp
        );

        //////////////////////////

        emit TrainInStation(_trainAddress, block.number);
        ///@dev review OoO

        lastStation[_trainAddress].lastGas = (_g1 - (_g1 - gasleft()));
        lastStation[_trainAddress].price = _price;

        (bool s, ) = tx.origin.call{
            value: lastStation[_trainAddress].lastGas * 2
        }("gas money");

        return s;
    }

    function _offBoard(
        Ticket memory t,
        Train memory _train,
        address toWho
    ) internal returns (bool success) {
        uint256 _shares;

        //@dev oot incentivises predictability
        uint256 pYield = (IERC20(_train.meta.buybackToken).balanceOf(
            mainStation
        ) -
            _train.inCustody -
            lastStation[t.trainAddress].ownedQty) / _train.yieldSharesTotal;

        if (t.destination < block.number) {
            _shares = (t.destination - t.departure) * t.bagSize;
            success = IERC20(_train.meta.buybackToken).transfer(
                toWho,
                (pYield * _shares + t.bagSize)
            );
        } else {
            _shares = (block.number - t.departure) * t.bagSize;
            success = IERC20(globalToken).transfer(
                toWho,
                ((pYield * _shares + t.bagSize) * t.perUnit)
            );
        }
        return success;
    }

    function _withdrawBuybackToken(Train memory _train, address tOwner)
        internal
        returns (bool success)
    {
        IERC20 token = IERC20(_train.meta.buybackToken);
        uint256 q = lastStation[_train.meta.uniPool].ownedQty;
        if (q > 0) {
            success = token.transfer(tOwner, q);
        }
        if (success) {
            emit TrainConductorWithdrawal(
                address(token),
                _train.meta.buybackToken,
                q
            );
        }
    }

    function _getLastStation(address _train) public view returns (stationData) {
        return lastStation[_train];
    }

    function _isInStation(Train memory _train)
        internal
        view
        returns (bool inStation)
    {
        if (
            _train.config.cycleParams[0] +
                lastStation[_train.meta.uniPool].at ==
            block.number
        ) inStation = true;
    }
}
