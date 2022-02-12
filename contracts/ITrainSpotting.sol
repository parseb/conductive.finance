//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

interface ITrainSpotting {
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

    function _spottingParams(
        address baseToken,
        address bossContract,
        address uniRouter
    ) external returns (address, address);

    function _trainStation(
        Train memory train,
        uint256 price,
        uint256 g1
    ) external returns (bool);

    function _offBoard(
        Ticket memory ticket,
        Train memory train,
        address whoIs
    ) external returns (bool);

    function _withdrawBuybackToken(Train memory train, address trainOwner)
        external
        returns (bool);

    function _getLastStation(address _train)
        external
        view
        returns (stationData memory);

    function _isInStation(uint256, address) external view returns (bool);
}
