//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "Uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "Uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";

contract Ymarkt is Ownable {
    /// @dev Uniswap V3 Factory address used to validate token pair and price

    IUniswapV3Factory uniswapV3 =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    IUniswapV3PoolImmutables poolBasicMeta;

    struct operators {
        address poolOwner; //address of the pool owner/creator
        address yVault; //address of yVault if any
        address denominatorToken; //quote token contract address
        address buybackToken; //buyback token contract address
        address uniPool; //address of the uniswap pool ^
    }

    /// @dev loop on cycle or update state on withdrawal
    struct configdata {
        uint32 cycleFreq; // sleepy blocks nr of
        uint32 minDistance; //min distance of block travel for reward
        uint16 budgetSlicer; // spent per cycle % (0 - 10000 0.01%-100%)
        uint16 upperRewardBound; // upper reward bound determiner
    }

    struct Train {
        operators meta;
        uint256 yieldSharesTotal; //increments on cycle, decrements on offboard
        uint64 passengers; //unique participants/positions
        uint64 budget; //total disposable budget
        uint64 inCustody; //total bag volume
        configdata config; //configdata
    }

    struct Ticket {
        uint64 destination; //promises to travel to block
        uint64 departure; // created on block
        uint32 rewarded; //number of times in reward space
        uint32 bagSize; //amount token
        uint64 perUnit; //buyout price
        address trainAddress; //train ID (pair pool)
    }

    /// @notice gets Ticket of [user] for [train]
    mapping(address => mapping(address => Ticket)) userTrainTicket;

    /// @notice get Train by address
    mapping(address => Train) getTrainByPool;

    /// @notice when last cycle was run for pool
    mapping(address => uint64) lastStation;

    /// @notice tickets fetchable by perunit price
    mapping(uint64 => Ticket[]) public ticketsFromPrice;

    constructor() {}

    ////////////////////////////////
    ///////  ERRORS

    error AlreadyOnThisTrain(address train);
    error NotOnThisTrain(address train);
    error ZeroValuesNotAllowed();
    error TrainNotFound(address ghostTrain);
    //////  Errors
    ////////////////////////////////

    ////////////////////////////////
    ///////  EVENTS

    //////  Events
    ////////////////////////////////

    ////////////////////////////////
    ////////  MODIFIERS

    modifier ensureTrain(address _train) {
        if (getTrainByPool[_train].meta.uniPool == address(0)) {
            revert TrainNotFound(_train);
        }
        _;
    }

    /// @dev ensure offboarding nulls ticket / destination
    modifier onlyUnticketed(address _train) {
        if (userTrainTicket[msg.sender][_train].destination > 0)
            revert AlreadyOnThisTrain(_train);
        _;
    }

    modifier onlyTicketed(address _train) {
        if (userTrainTicket[msg.sender][_train].destination == 0)
            revert NotOnThisTrain(_train);
        _;
    }

    modifier onlyExpiredTickets(address _train) {
        require(
            userTrainTicket[msg.sender][_train].destination < block.number,
            "Train is Moving"
        );
        _;
    }

    ///////   Modifiers
    /////////////////////////////////

    /////////////////////////////////
    ////////  PUBLIC FUNCTIONS

    function createTrain(
        address _buybackToken,
        address _budgetToken,
        uint24 _uniTier,
        address _yVault,
        uint32 _cycleFreq,
        uint32 _minDistance,
        uint16 _budgetSlicer,
        uint16 _upperRewardBound
    ) public returns (bool successCreated) {
        if (
            _cycleFreq <= 1 ||
            _minDistance <= 1 ||
            _budgetSlicer == 0 ||
            _upperRewardBound == 0
        ) {
            revert ZeroValuesNotAllowed();
        }

        address uniPool = isValidPool(_buybackToken, _budgetToken, _uniTier);

        if (uniPool == address(0)) {
            uniPool = uniswapV3.createPool(
                _buybackToken,
                _budgetToken,
                _uniTier
            );
        }

        require(uniPool != address(0), "invalid pair or tier");

        getTrainByPool[uniPool] = Train({
            meta: operators({
                poolOwner: msg.sender,
                yVault: _yVault,
                denominatorToken: _budgetToken,
                buybackToken: _buybackToken,
                uniPool: uniPool
            }),
            yieldSharesTotal: 0,
            passengers: 0,
            budget: 0,
            inCustody: 0,
            config: configdata({
                cycleFreq: _cycleFreq,
                minDistance: _minDistance,
                budgetSlicer: _budgetSlicer,
                upperRewardBound: 0
            })
        });

        successCreated = true;
    }

    function createTicket(
        uint64 _stations, // how many cycles
        uint32 _bagSize, // nr of tokens
        uint64 _perUnit, // target price
        address _trainAddress // train address
    )
        public
        payable
        ensureTrain(_trainAddress)
        onlyUnticketed(_trainAddress)
        returns (bool success)
    {
        if (
            _stations == 0 ||
            _bagSize == 0 ||
            _perUnit == 0 ||
            _trainAddress == address(0)
        ) {
            revert ZeroValuesNotAllowed();
        }

        Train memory train = getTrainByPool[_trainAddress];

        ///trainexists modifier

        uint64 _departure = uint64(block.number);
        uint64 _destination = _stations *
            uint64(train.config.cycleFreq) +
            _departure;

        Ticket memory ticket = Ticket({
            destination: _destination,
            departure: _departure,
            rewarded: 0,
            bagSize: _bagSize,
            perUnit: _perUnit,
            trainAddress: _trainAddress
        });

        userTrainTicket[msg.sender][_trainAddress] = ticket;

        incrementPassengers(_trainAddress);
        incrementBag(_trainAddress, _bagSize);

        ticketsFromPrice[_perUnit].push(ticket);

        success = true;
    }

    //////// Public Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  PRIVATE FUNCTIONS

    function incrementPassengers(address _trainId) private {
        getTrainByPool[_trainId].passengers++;
    }

    function decrementPassengers(address _trainId) private {
        getTrainByPool[_trainId].passengers--;
    }

    function incrementBag(address _trainId, uint64 _bagSize) private {
        getTrainByPool[_trainId].inCustody += _bagSize;
    }

    //////// Private Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  VIEW FUNCTIONS

    /// @param _bToken address of the base token
    /// @param _denominator address of the quote token
    /// @param  _tier  uniswap tier (500, 3000 ...) default: 3000
    function isValidPool(
        address _bToken,
        address _denominator,
        uint24 _tier
    ) public view returns (address poolAddress) {
        poolAddress = uniswapV3.getPool(_bToken, _denominator, _tier);
    }

    function getTicket(address _user, address _train)
        public
        view
        returns (Ticket memory ticket)
    {
        ticket = userTrainTicket[_user][_train];
    }

    function getTrain(address _trainAddress)
        public
        view
        returns (Train memory train)
    {
        train = getTrainByPool[_trainAddress];
    }
}

//////// View Functions
//////////////////////////////////
