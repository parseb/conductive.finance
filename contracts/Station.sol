//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "./UniswapInterfaces.sol";
import "./ITrainSpotting.sol";

contract TrainSpotting is ITrainSpotting {
    mapping(address => stationData) public lastStation;

    address globalToken;
    address centralStation;
    IUniswapV2Router02 solidRouter;

    constructor(address _denominator, address _router) {
        solidRouter = IUniswapV2Router02(_router);
        globalToken = _denominator;
    }

    function _spottingParams(
        address _denominator,
        address _centralStation,
        address _reRouter
    ) internal returns (address, address) {
        require(msg.sender == centralStation || centralStation == address(0));
        globalToken = _denominator;
        centralStation = _centralStation;
        if (_reRouter != address(0))
            solidRouter = IUniswapV2Router02(_reRouter);
        if (_denominator != address(0)) globalToken = _denominator;
        return (address(solidRouter), globalToken);
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
    ) internal returns (bool) {
        require(msg.sender == centralStation);

        ///////////////////////////////////////////
        ////////  first departure
        address _trainAddress = _train.meta.uniPool;

        if (lastStation[_trainAddress].lastGas == 0) {
            lastStation[_trainAddress].price =
                _price /
                (10**(18 - _train.config.cycleParams[3]));
            lastStation[_trainAddress].ownedQty = IERC20(
                _train.meta.buybackToken
            ).balanceOf(centralStation);

            lastStation[_trainAddress].lastGas = _g1 - gasleft();
            return true;
        }

        ////////////////////////////////////////////////////////////////////
        uint256 remaining = IERC20(_train.meta.buybackToken).balanceOf(
            centralStation
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
            centralStation,
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
    ) external returns (bool success) {
        require(msg.sender == centralStation);

        uint256 _shares;

        //@dev oot incentivises predictability
        uint256 pYield = (IERC20(_train.meta.buybackToken).balanceOf(
            centralStation
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

    function _getLastStation(address _train)
        external
        view
        returns (stationData memory)
    {
        return lastStation[_train];
    }

    function _isInStation(uint256 _cycleZero, address _trackAddr)
        external
        view
        returns (bool)
    {
        if (_cycleZero + lastStation[_trackAddr].at == block.number)
            return true;
    }
}
