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
        uint16 upperRewardBound; //look back cycles to pin max price as upper bound
        //uint16 compensatePeak; //charitable on new highs option - @dev deviation
    }

    struct Train {
        operators meta;
        uint256 yieldSharesTotal; //increments on cycle, decrements on offboard
        uint256 activeStakers; //unique participants/positions
        uint256 budget; //total disposable budget
        configdata config; //configdata
    }

    struct Ticket {
        uint64 destination; //promises to travel to block
        uint64 departure; // created on block
        uint32 rewarded; //number of times in reward space
        uint32 volume; //amount token
        uint64 offboardPrice; //offered price
        address poolAddress; //train ID
    }

    /// @notice get user position.
    /// @dev only 1 position per address
    mapping(address => Ticket) ticketUser;

    /// @notice get Train by uniPool address
    mapping(address => Train) getTrainByPool;

    /// @notice when last cycle was run for pool
    mapping(address => uint64) lastStation;

    constructor() {}

    /// @notice creates a new pool

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
        address uniPool = isValidPool(_buybackToken, _budgetToken, _uniTier);

        if (uniPool == address(0)) {
            uniPool = uniswapV3.createPool(
                _buybackToken,
                _budgetToken,
                _uniTier
            );
        }

        require(uniPool != address(0), "invalid token pair");

        Train memory train = Train({
            meta: operators({
                poolOwner: msg.sender,
                yVault: _yVault,
                denominatorToken: _budgetToken,
                buybackToken: _buybackToken,
                uniPool: uniPool
            }),
            yieldSharesTotal: 0,
            activeStakers: 0,
            budget: 0,
            config: configdata({
                cycleFreq: _cycleFreq,
                minDistance: _minDistance,
                budgetSlicer: _budgetSlicer,
                upperRewardBound: 0
            })
        });

        getTrainByPool[uniPool] = train;

        successCreated = true;
    }

    /// ####                #######################
    /// #### VIEW FUNCTIONS #######################
    /// ####                #######################

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
}
