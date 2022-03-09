//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./UniswapInterfaces.sol";
import "./ITrainSpotting.sol";
import "./StructsDataType.sol";
import "./IERC721.sol";

//import "./UniswapV2OracleLibrary.sol";

contract TrainSpotting {
    mapping(address => stationData) public lastStation;

    /// train -> ids
    mapping(address => uint256[]) offBoardingQueue;
    mapping(address => uint256[]) flaggedQueue;
    mapping(address => uint256[]) toBurnList;
    /// ticket Id -> price at flag
    mapping(uint256 => uint256) flaggedAt;
    mapping(uint256 => address) flaggedBy;

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
        require(centralStation == address(0) || centralStation == msg.sender);

        centralStation = _centralStation;
        IERC20(globalToken).approve(address(solidRouter), type(uint128).max);

        return (address(solidRouter), globalToken);
    }

    function _spottingParams(
        address _denominator,
        address _centralStation,
        address _reRouter
    ) external returns (address, address) {
        require(msg.sender == centralStation || centralStation == address(0));
        globalToken = _denominator;
        centralStation = _centralStation;
        if (_reRouter != address(0))
            solidRouter = IUniswapV2Router02(_reRouter);

        IERC20(globalToken).approve(
            address(solidRouter),
            type(uint128).max - 1
        );

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
        uint256 _inCustody,
        uint256 _yieldSharesTotal,
        uint256 _priceNow
    ) external returns (uint256[] memory bList) {
        require(msg.sender == centralStation);

        lastStation[addresses[1]].at = block.number;
        lastStation[addresses[1]].price = _priceNow;
        ////////////////////////////

        ///offboard
        for (uint256 i = 0; i < offBoardingQueue[addresses[1]].length; i++) {
            (bool b1, bytes memory r1) = centralStation.call(
                abi.encodeWithSignature(
                    "getTicketById(uint256)",
                    offBoardingQueue[addresses[1]][i]
                )
            );
            Ticket memory ti = abi.decode(r1, (Ticket));

            ///[t.destination, t.departure, t.bagSize, t.perUnit, inCustody, yieldSharesTotal]
            ///toWho, trainAddress, bToken
            if (
                b1 &&
                _offBoard(
                    [
                        ti.destination,
                        ti.departure,
                        ti.bagSize,
                        ti.perUnit,
                        _inCustody,
                        _yieldSharesTotal
                    ],
                    [ti.burner, addresses[1], addresses[0]]
                )
            ) toBurnList[addresses[1]].push(offBoardingQueue[addresses[1]][i]);
        }

        delete offBoardingQueue[addresses[1]];

        ///check and execute flags

        for (uint256 i = 0; i < flaggedQueue[addresses[1]].length; i++) {
            (bool b1, bytes memory r1) = centralStation.call(
                abi.encodeWithSignature(
                    "getTicketById(uint256)",
                    flaggedQueue[addresses[1]][i]
                )
            );
            Ticket memory tiF = abi.decode(r1, (Ticket));
            bool offboarded;
            if (_priceNow > tiF.perUnit) {
                if (_priceNow > flaggedAt[tiF.nftid]) {
                    IERC20(addresses[0]).approve(
                        flaggedBy[tiF.nftid],
                        IERC20(addresses[0]).allowance(
                            address(this),
                            flaggedBy[tiF.nftid]
                        ) + ((flaggedAt[tiF.nftid] - tiF.perUnit) * tiF.bagSize)
                    );
                }
                offboarded = _offBoard(
                    [
                        tiF.destination,
                        tiF.departure,
                        tiF.bagSize,
                        tiF.perUnit,
                        _inCustody,
                        _yieldSharesTotal
                    ],
                    [tiF.burner, addresses[1], addresses[0]]
                );
            }
            if (b1 && offboarded)
                toBurnList[addresses[1]].push(flaggedQueue[addresses[1]][i]);
            flaggedAt[tiF.nftid] = 0;
        }
        delete flaggedQueue[addresses[1]];
        /// swap train profit
        ///addLiquidity

        /// update state & return burn list
        ///////////////////////
        emit TrainInStation(addresses[1], block.number);

        lastStation[addresses[1]].price = getCummulativePrice(
            addresses[0],
            addresses[1]
        );
        lastStation[addresses[1]].timestamp = block.timestamp;
        // transfer pricipal to burner

        bList = toBurnList[addresses[1]];
        delete toBurnList[addresses[1]];
    }

    function getCummulativePrice(address _bToken, address _train)
        private
        returns (uint256 price)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_train);
        pair.sync();
        if (_bToken == pair.token0()) {
            price = pair.price0CumulativeLast();
        } else {
            price = pair.price1CumulativeLast();
        }
    }

    function _getPrice(address _bT, address _t) public returns (uint256 price) {
        require(msg.sender == centralStation);
        uint256 cummulativeNow = getCummulativePrice(_bT, _t);
        price =
            (cummulativeNow - lastStation[_t].price) /
            (block.timestamp - lastStation[_t].timestamp);
    }

    function _addToOffboardingList(uint256 _id, address _trainAddress)
        external
        returns (bool)
    {
        require(msg.sender == centralStation);
        offBoardingQueue[_trainAddress].push(_id);
        return true;
    }

    function _offBoard(
        uint256[6] memory params, ///[t.destination, t.departure, t.bagSize, t.perUnit, inCustody, yieldSharesTotal]
        address[3] memory addr ///toWho, trainAddress, bToken
    ) private returns (bool success) {
        //require(msg.sender == centralStation);

        uint256 shares;
        //@dev sharevalue degradation incentivises predictability
        if (
            (IERC20(addr[2]).balanceOf(address(this)) -
                params[4] -
                lastStation[addr[2]].ownedQty) > params[5]
        ) {
            uint256 pYield = (IERC20(addr[2]).balanceOf(address(this)) -
                params[4] -
                lastStation[addr[2]].ownedQty) / params[5];

            if (params[0] < block.number) {
                shares = (params[0] - params[1]) * params[2];
                success = IERC20(addr[2]).transfer(
                    addr[0],
                    (pYield * shares + params[2])
                );
            } else {
                shares = (block.number - params[1]) * params[2];
                success = IERC20(globalToken).transfer(
                    addr[0],
                    ((pYield * shares + params[2]) * params[3])
                );
            }
        } else {
            if (params[0] <= block.number)
                IERC20(addr[2]).transfer(addr[0], params[2]);
            if (params[0] > block.number)
                IERC20(globalToken).transfer(addr[0], params[2] * params[3]);
        }
        return success;
    }

    function _withdrawBuybackToken(address[3] memory addres)
        external
        returns (bool success)
    {
        IERC20 token = IERC20(addres[1]);
        uint256 q = lastStation[addres[0]].ownedQty;
        lastStation[addres[0]].ownedQty = 0;

        if (q > 0) success = token.transfer(addres[2], q);

        if (success)
            emit TrainConductorWithdrawal(addres[1], addres[0], addres[2], q);
        
    }

    function _flagTicket(
        uint256 _nftId,
        uint256 _atPrice,
        address _flagger
    ) external returns (bool _s) {
        require(msg.sender == centralStation);
        require(flaggedAt[_nftId] == 0, "Already Flagged");

        (bool b1, bytes memory r1) = centralStation.call(
            abi.encodeWithSignature("getTicketById(uint256)", _nftId)
        );

        Ticket memory t = abi.decode(r1, (Ticket));

        (bool b2, bytes memory r2) = centralStation.call(
            abi.encodeWithSignature("getTrain(address)", t.trainAddress)
        );
        require(t.perUnit < _atPrice, "under");

        Train memory train = abi.decode(r2, (Train));

        //require(t.trainAddress == train.tokenAndPool[1]);

        if (train.config.control[1])
            require(
                IERC721(centralStation).balanceOf(msg.sender) >= 1,
                "Unauthorized"
            );

        uint256 priceNow = _getPrice(
            train.tokenAndPool[0],
            train.tokenAndPool[1]
        );
        require(
            (priceNow > t.perUnit) && (priceNow >= _atPrice),
            "Invalid TWPrice"
        );
        flaggedAt[_nftId] = _atPrice;
        flaggedBy[_nftId] = _flagger;
        flaggedQueue[t.trainAddress].push(_nftId);

        return true;
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
            address(this),
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

    function _initL(address _yourToken, uint256[2] memory _ammounts)
        external
        returns (bool)
    {
        require(msg.sender == centralStation);

        (, , uint256 liq) = solidRouter.addLiquidity(
            _yourToken,
            globalToken,
            _ammounts[0],
            _ammounts[1],
            _ammounts[0],
            _ammounts[1],
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
        uint256 l = IERC20(_poolAddress).balanceOf(address(this));
        if (l > 100) {
            (uint256 a, uint256 b) = solidRouter.removeLiquidity(
                _bToken,
                globalToken,
                l,
                0,
                0,
                address(this),
                block.timestamp
            );
            if (a + b > 2) return true;
        }
    }

    function _tokenOut(
        uint256 _amount,
        uint256 _inCustody,
        address _poolAddress,
        address _bToken,
        address _toWho
    ) external returns (bool success) {
        require(msg.sender == centralStation);

        IERC20 token = IERC20(_bToken);
        uint256 prev = token.balanceOf(address(this));
        if (prev >= _amount) success = token.transfer(_toWho, _amount);
        if (!success) {
            uint256 _toBurn = IERC20(_poolAddress).balanceOf(address(this)) /
                (_inCustody / _amount);
            _removeLiquidity(_bToken, _amount, 0, _toBurn);
            success = token.transfer(_toWho, _amount);
        }
    }

    function _approveToken(address _bToken, address _uniPool)
        external
        returns (bool success)
    {
        require(msg.sender == centralStation);

        success =
            IERC20(_bToken).approve(
                address(solidRouter),
                type(uint256).max - 1
            ) &&
            IERC20(_uniPool).approve(
                address(solidRouter),
                type(uint256).max - 1
            );
    }

    function _willTransferFrom(
        address _from,
        address _to,
        address _token,
        uint256 _amount
    ) external returns (bool success) {
        require(msg.sender == centralStation);
        success = IERC20(_token).transferFrom(_from, _to, _amount);
    }

    function _setStartStation(address _trainAddress, address _bToken, uint256 _initQuantity)
        external
        returns (bool)
    {
        require(msg.sender == centralStation);
        lastStation[_trainAddress].at = block.number;
        lastStation[_trainAddress].price = getCummulativePrice(
            _bToken,
            _trainAddress
        );
        lastStation[_trainAddress].timestamp = block.timestamp;
        lastStation[_trainAddress].ownedQty = _initQuantity * 2;
        return true;
    }

    function _ensureNoDoubleEntry(address _trainA) external returns (bool s) {
        if (lastStation[_trainA].at < block.number) s = true;
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
            lastStation[_train].timestamp
        ];
    }

    function _isInStation(uint256 _cycleZero, address _trackAddr)
        external
        view
        returns (bool z)
    {
        if (_cycleZero + lastStation[_trackAddr].at <= block.number) z = true;
    }

    function _getFlaggedQueue(address _trainAddress)
        public
        view
        returns (uint256[] memory q)
    {
        q = flaggedQueue[_trainAddress];
    }

    function _getOffboardingQueue(address _trainAddress)
        public
        view
        returns (uint256[] memory q)
    {
        q = offBoardingQueue[_trainAddress];
    }
}
