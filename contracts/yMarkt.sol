//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "Uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract Ymarkt is Ownable {
    /// @dev Uniswap V3 Factory address used to validate token pair and price
    IUniswapV3Factory uniswapV3 =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct poolMeta {
        address poolOwner;
        address yVault;
        address denominatorToken;
        address buybackToken;
        address uniPool;
    }
    /// @dev loop on cycle or update state on withdrawal
    struct configdata {
        uint32 cycleFreq; // sleepy blocks nr of
        uint32 minDistance; //min distance of block travel for reward
        uint64 budgetSlicer; // spent per cycle %
        uint16 upperRewardBound; //look back cycles to pin max price as upper bound
        uint16 compensatePeak; //charitable on new highs option - @dev deviation
    }

    struct Pool {
        poolMeta meta;
        uint256 yieldSharesTotal; //increments on reward, arbitrage, positioncreation, decrements on withdraw
        uint256 activeStakers;
        uint256 budget;
        configdata config;
    }

    struct Ticket {
        uint64 destination; //promises to travel to block
        uint64 departure; // created on block
        uint32 rewarded; //number of times in reward space
        uint32 volume; //amount token
        uint64 offboardPrice; //offered price
    }

    /// @notice get user position.
    /// @dev only 1 position per address
    mapping(address => Ticket) ticketUser;

    /// @notice get pool by uniPool address
    mapping(address => Pool) getPool;

    /// @notice when last cycle was run for pool
    mapping(address => uint64) lastCycled;

    constructor() {}

    /// ####                #######################
    /// #### VIEW FUNCTIONS #######################
    /// ####                #######################

    /// @param _bToken address of the base token
    /// @param _denominator address of the quote token
    /// @dev might be unnecesary 13366331
    function isValidPool(address _bToken, address _denominator)
        public
        view
        returns (bool isValid)
    {
        uint24 fee = 3000;
        address pool;
        pool = uniswapV3.getPool(_bToken, _denominator, fee);

        if (pool != address(0)) isValid = true;
    }
}
