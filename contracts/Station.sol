//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "./UniswapInterfaces.sol";
import "./ITrainSpotting.sol";
import "./StructsDataType.sol";

contract TrainSpotting {
    mapping(address => stationData) public lastStation;

    address globalToken;
    address centralStation;
    IUniswapV2Router02 solidRouter;

    constructor(address _denominator, address _router) {
        solidRouter = IUniswapV2Router02(_router);
        globalToken = _denominator;
    }

    function _setCentralStation(address _centralStation)
        external
        returns (address, address)
    {
        require(centralStation == address(0));
        centralStation = _centralStation;
        return (address(solidRouter), globalToken);
    }

    function _spottingParams(
        address _denominator,
        address _centralStation,
        address _reRouter
    ) external returns (address, address) {
        require(msg.sender == centralStation || centralStation == address(0));
        if (globalToken == address(0)) globalToken = _denominator;
        centralStation = _centralStation;
        if (_reRouter != address(0))
            solidRouter = IUniswapV2Router02(_reRouter);

        emit SpottingParamsUpdated(globalToken, centralStation);

        return (address(solidRouter), globalToken);
    }

    event TrainInStation(address indexed _trainAddress, uint256 _nrstation);
    event TrainStarted(address indexed _trainAddress, stationData _station);
    event TrainConductorWithdrawal(
        address indexed buybackToken,
        address indexed trainAddress,
        address who,
        uint256 quantity
    );
    event TrainStarted(address indexed _trainAddress, Train _train);
    event SpottingParamsUpdated(
        address _denominator,
        address indexed _centralStation
    );

    function _trainStation(
        address[2] memory addresses,
        uint256[5] memory context
    ) external returns (bool) {
        require(msg.sender == centralStation);

        ///////////////////////////////////////////
        ////////  first departure

        if (lastStation[addresses[0]].lastGas == 0) {
            lastStation[addresses[0]].price =
                context[0] /
                (10**(18 - context[3]));
            lastStation[addresses[0]].ownedQty = IERC20(addresses[1]).balanceOf(
                centralStation
            );

            lastStation[addresses[0]].lastGas = context[1] - gasleft();
            return true;
        }

        ////////////////////////////////////////////////////////////////////
        uint256 remaining = IERC20(addresses[1]).balanceOf(centralStation);

        uint256 card = context[2];
        uint64 percentage = uint64(context[4]);
        if (context[2] > 0)
            context[2] = context[2] - ((percentage * context[2]) / 100);

        card = card - context[2];
        uint256 price2 = IUniswapV2Pair(addresses[0]).price0CumulativeLast();
        card = card / price2;
        lastStation[addresses[0]].ownedQty += card;

        /// ^ ? wut
        /// add liquidity. buyback using slice of budget

        solidRouter.addLiquidity(
            addresses[1],
            globalToken,
            IERC20(addresses[1]).balanceOf(address(this)),
            IERC20(globalToken).balanceOf(address(this)),
            0,
            0,
            centralStation,
            block.timestamp
        );

        //////////////////////////

        emit TrainInStation(addresses[0], block.number);
        ///@dev review OoO

        lastStation[addresses[0]].lastGas = (context[1] -
            (context[1] - gasleft()));
        lastStation[addresses[0]].price = context[0];

        (bool s, ) = tx.origin.call{
            value: lastStation[addresses[0]].lastGas * 2
        }("gas money");

        return s;
    }

    function _offBoard(
        uint256[6] memory params, ///[t.destination, t.departure, t.bagSize, t.perUnit, inCustody, yieldSharesTotal]
        address[3] memory addresses ///toWho, trainAddress, bToken
    ) external returns (bool success) {
        require(msg.sender == centralStation);

        uint256 shares;
        //@dev sharevalue degradation incentivises predictability
        uint256 pYield = (IERC20(addresses[2]).balanceOf(centralStation) -
            params[4] -
            lastStation[addresses[2]].ownedQty) / params[5];

        if (params[0] < block.number) {
            shares = (params[0] - params[1]) * params[2];
            success = IERC20(addresses[2]).transfer(
                addresses[0],
                (pYield * shares + params[2])
            );
        } else {
            shares = (block.number - params[1]) * params[2];
            success = IERC20(globalToken).transfer(
                addresses[0],
                ((pYield * shares + params[2]) * params[3])
            );
        }
        return success;
    }

    function _withdrawBuybackToken(address[3] memory addresses)
        external
        returns (bool success)
    {
        IERC20 token = IERC20(addresses[1]);
        uint256 q = lastStation[addresses[0]].ownedQty;
        if (q > 0) {
            success = token.transfer(addresses[2], q);
        }
        if (success)
            emit TrainConductorWithdrawal(
                addresses[1],
                addresses[0],
                addresses[2],
                q
            );
    }

    function _addLiquidity(
        address _bToken,
        uint256 _bAmout,
        uint256 _dAmout
    ) external returns (bool) {
        require(msg.sender == centralStation);

        (, , uint256 liq) = solidRouter.addLiquidity(
            _bToken,
            globalToken,
            _bAmout,
            _dAmout,
            0,
            0,
            centralStation,
            block.timestamp
        );
        if (liq > 1) return true;
    }

    function _removeLiquidity(
        address _bToken,
        uint256 _bAmount,
        uint256 _dAmount,
        uint256 _lAmount
    ) public returns (bool) {
        require(msg.sender == centralStation);

        (, uint256 liq) = solidRouter.removeLiquidity(
            _bToken,
            globalToken,
            _lAmount,
            _bAmount,
            _dAmount,
            address(this),
            block.timestamp
        );
        if (liq > 1) return true;
    }

    function _removeAllLiquidity(address _bToken, address _poolAddress)
        external
        returns (bool)
    {
        require(msg.sender == centralStation);

        (uint256 a, uint256 b) = solidRouter.removeLiquidity(
            _bToken,
            globalToken,
            IERC20(_poolAddress).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        if (a + b > 2) return true;
    }

    function _tokenOut(
        uint256 _amount,
        uint256 _inCustody,
        address _poolAddress,
        address _bToken
    ) external returns (bool success) {
        require(msg.sender == centralStation);

        IERC20 token = IERC20(_bToken);
        uint256 prev = token.balanceOf(address(this));
        if (prev >= _amount) success = token.transfer(msg.sender, _amount);
        if (!success) {
            uint256 _toBurn = IERC20(_poolAddress).balanceOf(address(this)) /
                (_inCustody / _amount);
            _removeLiquidity(_bToken, _amount, 0, _toBurn);
            success = token.transfer(msg.sender, _amount);
        }
    }

    function _approveToken(address _bToken) external returns (bool success) {
        require(msg.sender == centralStation);

        success = IERC20(_bToken).approve(
            address(solidRouter),
            type(uint128).max - 1
        );
    }

    function _getLastStation(address _train)
        external
        view
        returns (uint256[4] memory stationD)
    {
        stationD = [
            lastStation[_train].at,
            lastStation[_train].price,
            lastStation[_train].ownedQty,
            lastStation[_train].lastGas
        ];
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
