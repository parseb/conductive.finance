//SPDX-License-Identifier: UNLICENCED
pragma solidity ^0.8.4;

struct stationData {
    uint256 at; //last station ocurred at block
    uint256 price; //price at last station
    uint256 ownedQty; //owned quantity (withdrawable by conductor / ! inCustody)
    uint256 timestamp; //for intrastation twap
}

struct configdata {
    uint64[2] cycleParams; //[cycleFreq(distance between stations), minDistance(min nr of stations for ticket)
    uint64[2] revenueParams; //[miners, trainowner]
    uint128 minBagSize; //min bag size (min stake for ticket)
    bool[2] control; // [configdataCanBeChanged, memberFlaggingOnly]
}

struct Train {
    address[2] tokenAndPool; //token and pool contract address
    uint256 yieldSharesTotal; //total quantity of pool shares
    uint256 inCustody; //total token in custody (! separate from stationData.ownedQty)
    uint64 passengers; //number of active tickets/passangers
    configdata config; //configdata
}

struct Ticket {
    uint256 destination; //promises to travel to block
    uint256 departure; //created on block
    uint256 bagSize; //amount token
    uint256 perUnit; //buyout price
    address trainAddress; //train ID (pair pool)
    uint256 nftid; //nft id
    address burner; //has right to burn
}
