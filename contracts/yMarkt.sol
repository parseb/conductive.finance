//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "Uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "Uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
//import {VaultAPI, BaseWrapper} from "@yearnvaults/contracts/BaseWrapper.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";

contract Ymarkt is Ownable, ReentrancyGuard {
    /// @dev Uniswap V3 Factory address used to validate token pair and price

    IUniswapV3Factory uniswapV3 =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    //IUniswapV3PoolImmutables poolBasicMeta;

    struct operators {
        address trainConductor; //address of the pool owner/creator
        address denominatorToken; //quote token contract address
        address buybackToken; //buyback token contract address
        address uniPool; //address of the uniswap pool ^
        address yVault; //address of yVault if any
    }

    struct configdata {
        uint32 cycleFreq; // sleepy blocks nr of
        uint32 minDistance; //min distance of block travel for reward
        uint16 budgetSlicer; // spent per cycle % (0 - 10000 0.01%-100%)
        uint16 upperRewardBound; // upper reward bound determiner
        uint32 minBagSize; // min bag size
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
        uint64 destination; //promises to travel to block
        uint64 departure; // created on block
        uint32 rewarded; //number of times in reward space
        uint256 bagSize; //amount token
        uint256 perUnit; //buyout price
        address trainAddress; //train ID (pair pool)
    }

    /// @notice gets Ticket of [user] for [train]
    mapping(address => mapping(address => Ticket)) userTrainTicket;

    /// @notice get Train by address
    mapping(address => Train) getTrainByPool;

    /// @notice when last cycle was run for pool
    mapping(address => uint64) lastStation;

    /// @notice tickets fetchable by perunit price
    mapping(address => mapping(uint256 => Ticket[])) ticketsFromPrice;

    constructor() {}

    ////////////////////////////////
    ///////  ERRORS

    error AlreadyOnThisTrain(address train);
    error NotOnThisTrain(address train);
    error ZeroValuesNotAllowed();
    error TrainNotFound(address ghostTrain);
    error IssueOnDeposit(uint256 amount, address token);
    error MinDepositRequired(uint256 required, uint256 provided);

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

    modifier ensureBagSize(uint256 _bagSize, address _train) {
        if (_bagSize < getTrainByPool[_train].config.minBagSize)
            revert MinDepositRequired(
                getTrainByPool[_train].config.minBagSize,
                _bagSize
            );
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
        uint16 _upperRewardBound,
        uint32 _minBagSize
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
                trainConductor: msg.sender,
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
                upperRewardBound: _upperRewardBound,
                minBagSize: _minBagSize
            })
        });

        successCreated = true;

        /// @dev emit event
        /// @dev add vaults. check if any. create if not. tbd if value added
    }

    function createTicket(
        uint64 _stations, // how many cycles
        uint256 _perUnit, // target price
        address _trainAddress, // train address
        uint256 _bagSize // nr of tokens
    )
        public
        payable
        ensureTrain(_trainAddress)
        ensureBagSize(_bagSize, _trainAddress)
        onlyUnticketed(_trainAddress)
        nonReentrant
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
        require(train.meta.uniPool != address(0), "Train not found");

        if (_bagSize < train.config.minBagSize)
            revert MinDepositRequired(train.config.minBagSize, _bagSize);

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

        ticketsFromPrice[_trainAddress][_perUnit].push(ticket);

        success = true;
    }

    //////// Public Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  PRIVATE FUNCTIONS

    function depositsBag(uint256 _bagSize, address _trainID)
        private
        returns (bool success)
    {
        IERC20 token = IERC20(_trainID);
        uint256 _prevBalance = token.balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), _bagSize));
        require(token.balanceOf(address(this)) >= _prevBalance + _bagSize);
        success = true;
    }

    function incrementPassengers(address _trainId) private {
        getTrainByPool[_trainId].passengers++;
    }

    function decrementPassengers(address _trainId) private {
        getTrainByPool[_trainId].passengers--;
    }

    function incrementBag(address _trainId, uint256 _bagSize) private {
        getTrainByPool[_trainId].inCustody += _bagSize;
    }

    function decrementBag(address _trainId, uint256 _bagSize) private {
        getTrainByPool[_trainId].inCustody -= _bagSize;
    }

    function getTicketsByPrice(address _train, uint64 _perPrice)
        public
        view
        returns (Ticket[] memory)
    {
        return ticketsFromPrice[_train][_perPrice];
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
