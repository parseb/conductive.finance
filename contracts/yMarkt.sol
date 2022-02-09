//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20Metadata.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/token/ERC721/ERC721.sol";
import "./ISolidly.sol";

//import "./UniswapInterfaces.sol";

contract Conductive is
    Ownable,
    ReentrancyGuard,
    ERC721("conductive.finance", "Train")
{
    /// @dev Uniswap V3 Factory address used to validate token pair and price

    uint256 clicker;

    Ticket[] public allTickets;
    //Train[] public allTrains;

    mapping(address => Ticket[]) public offBoardingQueue;

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

    struct stationData {
        uint256 at;
        uint256 price;
        uint256 ownedQty;
        uint256 lastGas;
    }

    /// @notice last station data
    mapping(address => stationData) public lastStation;

    /// @notice tickets fetchable by perunit price
    mapping(address => mapping(uint256 => Ticket)) ticketFromPrice;

    /// @notice gets Ticket of [user] for [train]
    mapping(address => mapping(address => Ticket)) userTrainTicket;

    /// @notice get Train by address
    mapping(address => Train) getTrainByPool;

    /// @notice fetch ticket from nftid [account,trainId]
    mapping(uint256 => address[2]) ticketByNftId;

    /// @notice stores train owner
    mapping(address => address) isTrainOwner;

    /// @notice stores after what block conductor will be able to withdraw howmuch of buybacked token
    mapping(address => uint256) allowConductorWithdrawal; //[block]

    IBaseV1Factory public immutable baseFactory;
    IBaseV1Router public immutable solidRouter;
    /// @dev reduces security risks - base chain token
    address public immutable globalToken;

    constructor(
        address _factory,
        address _router,
        address _globalDenominator
    ) {
        baseFactory = IBaseV1Factory(_factory);
        solidRouter = IBaseV1Router(_router);

        require(IERC20Metadata(_globalDenominator).decimals() == 18);
        globalToken = _globalDenominator;

        clicker = 1;
    }

    receive() external payable {
        if (owner() != address(0)) {
            payable(owner()).call{value: msg.value};
        } else revert("tomato, potato later");
    }

    ////////////////

    // function updateEnvironment(
    //     address _poolFactory,
    //     address _vRegistry,
    //     address _router
    // ) public onlyOwner {
    //     require(_poolFactory != address(0) && _vRegistry != address(0));

    //     baseFactory = IBaseV1Factory(_poolFactory);
    //     yRegistry = IV2Registry(_vRegistry);
    //     solidRouter = IUniswapV2Router02(_router);
    //     emit RailNetworkChanged(address(baseFactory), _poolFactory);
    // }

    ////////////////////////////////
    ///////  ERRORS

    error AlreadyOnThisTrain(address train);
    error NotOnThisTrain(address train);
    error ZeroValuesNotAllowed();
    error TrainNotFound(address ghostTrain);
    error IssueOnDeposit(uint256 amount, address token);
    error MinDepositRequired(uint256 required, uint256 provided);
    error NotTrainOwnerError(address _train, address _perp);
    error PriceNotUnique(address _train, uint256 _price);
    //////  Errors
    ////////////////////////////////

    ////////////////////////////////
    ///////  EVENTS

    event FallbackCall(address _sender, bytes _data);

    event TrainCreated(
        address indexed _trainAddress,
        address indexed _buybackToken
    );

    event TicketCreated(
        address _passanger,
        address indexed _trainAddress,
        uint256 indexed _perUnit
    );

    event TicketBurned(
        address indexed _passanger,
        address indexed _trainAddress,
        uint256 _nftid
    );

    event TrainInStation(address indexed _trainAddress, uint256 _nrstation);

    event JumpedOut(
        address indexed _who,
        address indexed _ofTrain,
        uint256 indexed _nftID
    );

    event TrainConductorBeingWeird(
        uint256 quantity,
        address indexed train,
        address indexed conductor
    );

    event TrainConductorWithdrawal(
        address buybackToken,
        address trainAddress,
        uint256 quantity
    );

    event RailNetworkChanged(address indexed _from, address indexed _to);

    event TrainParamsChanged(
        address indexed _trainAddress,
        uint64[4] _newParams
    );

    event TrainStarted(address indexed _trainAddress, stationData _station);
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

    modifier zeroNotAllowed(uint64[4] memory _params) {
        for (uint8 i = 0; i < 4; i++) {
            if (_params[i] < 1) revert ZeroValuesNotAllowed();
        }
        _;
    }

    modifier onlyTrainOnwer(address _train) {
        if (!(isTrainOwner[_train] == msg.sender))
            revert NotTrainOwnerError(_train, msg.sender);
        _;
    }

    modifier priceIsUnique(address _train, uint256 _price) {
        if (ticketFromPrice[_train][_price].bagSize != 0)
            revert PriceNotUnique(_train, _price);
        _;
    }

    ///////// Modifiers
    //////////////////////////////

    function changeTrainParams(
        address _trainAddress,
        uint64[4] memory _newparams
    )
        public
        onlyTrainOnwer(_trainAddress)
        zeroNotAllowed(_newparams)
        returns (bool)
    {
        Train memory train = getTrainByPool[_trainAddress];

        if (train.config.controlledSpeed) {
            train.config.cycleParams = _newparams;
            getTrainByPool[_trainAddress] = train;

            emit TrainParamsChanged(_trainAddress, _newparams);
            return true;
        } else {
            revert("Immutable Train");
        }
    }

    ///////   Modifiers
    /////////////////////////////////

    /////////////////////////////////
    ////////  PUBLIC FUNCTIONS

    function createTrain(
        address _buybackToken,
        uint64[4] memory _cycleParams,
        uint256 _minBagSize,
        bool _levers
    ) public zeroNotAllowed(_cycleParams) returns (bool successCreated) {
        require(_cycleParams[0] > 10); //@dev mincycle hardcoded for jump
        require(_cycleParams[2] > 1 && _cycleParams[2] < 100);

        address uniPool = baseFactory.getPair(
            _buybackToken,
            globalToken,
            false
        );
        if (uniPool == address(0)) {
            uniPool = baseFactory.createPair(_buybackToken, globalToken, false);
        }

        require(uniPool != address(0));
        //trainAddressVault[uniPool] = IVault(tokenHasVault(_buybackToken));
        require(getTrainByPool[uniPool].meta.uniPool == address(0), "exists");

        Train memory _train = Train({
            meta: operators({buybackToken: _buybackToken, uniPool: uniPool}),
            yieldSharesTotal: 0,
            passengers: 0,
            budget: 0,
            inCustody: 0,
            config: configdata({
                cycleParams: _cycleParams,
                minBagSize: _minBagSize,
                controlledSpeed: _levers
            })
        });

        getTrainByPool[uniPool] = _train;
        isTrainOwner[uniPool] = msg.sender;
        lastStation[uniPool].at = block.number;
        //lastStation[uniPool].price = getTokenPrice(uniPool);

        IERC20(_train.meta.buybackToken).approve(
            address(solidRouter),
            type(uint128).max - 1
        );
        IERC20(globalToken).approve(
            address(solidRouter),
            type(uint128).max - 1
        );

        //allTrains.push(_train);
        emit TrainCreated(uniPool, _buybackToken);
        successCreated = true;
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
        onlyUnticketed(_trainAddress)
        nonReentrant
        returns (bool success)
    {
        require(!isInStation(_trainAddress), "wait");
        if (
            _stations == 0 ||
            _bagSize == 0 ||
            _perUnit == 0 ||
            _trainAddress == address(0)
        ) {
            revert ZeroValuesNotAllowed();
        }

        if (ticketFromPrice[_trainAddress][_perUnit].bagSize != 0)
            revert PriceNotUnique(_trainAddress, _perUnit);

        Train memory train = getTrainByPool[_trainAddress];
        uint256 minPrice = 10 **
            (IERC20Metadata(globalToken).decimals() -
                train.config.cycleParams[3]);
        require(minPrice <= _perUnit, "too low");

        if (_bagSize < train.config.minBagSize)
            revert MinDepositRequired(train.config.minBagSize, _bagSize);

        bool transfer = IERC20(train.meta.buybackToken).transferFrom(
            msg.sender,
            address(this),
            _bagSize
        );

        if (!transfer)
            revert IssueOnDeposit(_bagSize, address(train.meta.buybackToken));

        Ticket memory ticket = Ticket({
            destination: (_stations * train.config.cycleParams[0]) +
                uint64(block.number),
            departure: uint64(block.number),
            bagSize: _bagSize,
            perUnit: _perUnit,
            trainAddress: _trainAddress,
            nftid: clicker
        });

        _safeMint(msg.sender, clicker);

        userTrainTicket[msg.sender][_trainAddress] = ticket;
        ticketFromPrice[_trainAddress][
            ticket.perUnit / (10**train.config.cycleParams[3])
        ] = ticket;
        ticketByNftId[clicker] = [msg.sender, _trainAddress];
        allTickets.push(ticket);

        incrementPassengers(_trainAddress);
        incrementBag(_trainAddress, _bagSize);
        incrementShares(
            _trainAddress,
            (ticket.destination - uint64(block.number)),
            _bagSize
        );

        clicker++;

        success = true;
        emit TicketCreated(msg.sender, _trainAddress, ticket.perUnit);
    }

    function burnTicket(address _train)
        public
        onlyTicketed(_train)
        nonReentrant
        returns (bool success)
    {
        require(!isInStation(_train), "please wait");
        Ticket memory ticket = userTrainTicket[msg.sender][_train];
        require(ticket.bagSize > 0, "Already Burned");
        require(
            ticket.departure + 10 < block.number,
            "doors are still closing"
        );
        Train memory train = getTrainByPool[ticket.trainAddress];

        success = tokenOut(ticket.bagSize, train);
        if (success) {
            _burn(ticket.nftid);
            emit JumpedOut(msg.sender, _train, ticket.nftid);
        }
    }

    ///@dev gas war - feature or bug?
    function trainStation(address _trainAddress)
        public
        nonReentrant
        returns (bool)
    {
        uint256 g1 = gasleft();
        require(lastStation[_trainAddress].at != block.number, "Departing");
        require(isInStation(_trainAddress), "Train moving. (Chu, Chu)");

        Train memory train = getTrainByPool[_trainAddress];

        uint256 pYield;
        uint256 _price = IBaseV1Pair(train.meta.uniPool).current(
            train.meta.buybackToken,
            (10**IERC20Metadata(train.meta.buybackToken).decimals())
        );

        ///////////////////////////////////////////
        ////////  causa sui

        if (lastStation[_trainAddress].lastGas == 0) {
            lastStation[_trainAddress].lastGas = 1;
            lastStation[_trainAddress].at = block.number;
            lastStation[_trainAddress].price = _price;
            lastStation[_trainAddress].ownedQty = IERC20(
                train.meta.buybackToken
            ).balanceOf(address(this));

            solidRouter.addLiquidity(
                train.meta.buybackToken,
                globalToken,
                false,
                IERC20(train.meta.buybackToken).balanceOf(address(this)),
                IERC20(globalToken).balanceOf(address(this)) - train.budget,
                0,
                0,
                address(this),
                block.timestamp
            );

            emit TrainStarted(_trainAddress, lastStation[_trainAddress]);

            return true;
        }

        IBaseV1Pair(_trainAddress).burn(address(this));

        //////////////////////////////////////////////////////////////////////////
        /// conductor withdrawal

        withdrawBuybackToken(_trainAddress);

        ////////////////////////////////////////////////////////////////////
        /// orderly disemark

        pYield =
            (IERC20(train.meta.buybackToken).balanceOf(address(this)) -
                train.inCustody) /
            train.yieldSharesTotal;

        /// offboarding queue
        offBoardingPrep(
            _trainAddress,
            _price / (10**(18 - train.config.cycleParams[3]))
        );

        for (uint256 i = 0; i < offBoardingQueue[_trainAddress].length; i++) {
            /// @dev fuzzy
            Ticket memory t = offBoardingQueue[_trainAddress][i];
            bool vested = t.destination < block.number;
            uint256 _shares;
            address toWho = ticketByNftId[t.nftid][0];
            if (vested) _shares = t.bagSize * (t.destination - t.departure);
            if (!vested) _shares = t.bagSize * (block.number - t.departure);

            if (vested) {
                IERC20(train.meta.buybackToken).transfer(
                    toWho,
                    (pYield * _shares + t.bagSize)
                );
            } else {
                IERC20(globalToken).transfer(
                    toWho,
                    ((pYield * _shares + t.bagSize) * t.perUnit)
                );
            }
            delete offBoardingQueue[_trainAddress][i];
            _burn(t.nftid);
        }

        //////  orderly disemark
        ////////////////////////////////////////////////////////////////////

        uint256 card = train.budget;
        uint64 percentage = train.config.cycleParams[2];
        if (train.budget > 0)
            train.budget = train.budget - ((percentage * train.budget) / 100);

        card = card - train.budget;
        card = card / _price;
        lastStation[_trainAddress].ownedQty += card;
        card =
            IERC20(train.meta.buybackToken).balanceOf(address(this)) -
            lastStation[_trainAddress].ownedQty;

        train.inCustody = card;

        /// add liquidity. buyback using slice of budget

        solidRouter.addLiquidity(
            address(IERC20(train.meta.buybackToken)),
            address(IERC20(globalToken)),
            false,
            card,
            train.budget,
            1,
            1,
            address(this),
            block.timestamp - 2
        );

        //////////////////////////

        emit TrainInStation(_trainAddress, block.number);
        ///@dev review OoO

        lastStation[_trainAddress].lastGas = (g1 - (g1 - gasleft()));

        return true;
    }

    function requestOffBoarding(address _trainAddress)
        public
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = userTrainTicket[msg.sender][_trainAddress];
        require(stationsLeft(ticket.nftid) <= 1, "maybe not next staton");

        offBoardingQueue[_trainAddress].push(ticket);
        Ticket memory emptyticket;
        //userTrainTicket[msg.sender][_trainAddress] = emptyticket;
        success = true;
    }

    /// @notice announces withdrawal intention on buybacktoken only
    /// @dev rugpulling timelock intention
    /// @param _trainAddress address of train
    /// @param _quantity uint256 amount of tokens to withdraw
    function conductorWithdrawal(
        uint64 _quantity,
        uint64 _wen,
        address _trainAddress
    ) public onlyTrainOnwer(_trainAddress) {
        require(!isInStation(_trainAddress), "please wait");

        Train memory train = getTrainByPool[_trainAddress];
        /// @dev irrelevant if cyclelength is changeable
        require(_wen > 0, "never, cool");
        require(_quantity > 1, "swamp of nothingness");
        // require(lastStation[_trainAddress].ownedQty > _quantity, "never, cool");
        ///@notice case for 0 erc20 transfer .any?
        allowConductorWithdrawal[_trainAddress] =
            block.number +
            (train.config.cycleParams[0] * _wen);

        emit TrainConductorBeingWeird(_quantity, _trainAddress, msg.sender);
    }

    ////////### ERC721 Override

    ///////##########

    //////// Public Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  INTERNAL FUNCTIONS

    ///before ERC721 transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if (from != address(0) || to == address(0)) {
            Ticket memory emptyticket;
            Ticket memory T = getTicketById(tokenId);
            uint256 toBurn = T.bagSize * (T.destination - T.departure);
            userTrainTicket[from][T.trainAddress] = emptyticket;
            decrementShares(T.trainAddress, toBurn);
            decrementBag(T.trainAddress, T.bagSize);
            decrementPassengers(T.trainAddress);
            ticketByNftId[T.nftid] = [address(0), address(0)];
        }
    }

    ////////  Internal Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  PRIVATE FUNCTIONS

    function tokenOut(uint256 _amount, Train memory train)
        private
        returns (bool success)
    {
        IERC20 token = IERC20(train.meta.buybackToken);
        uint256 prev = token.balanceOf(address(this));
        if (prev >= _amount) success = token.transfer(msg.sender, _amount);

        if (!success) {
            IBaseV1Pair(train.meta.uniPool).burn(address(this));

            success = token.transfer(msg.sender, _amount);
            IBaseV1Router(train.meta.uniPool).addLiquidity(
                address(token),
                train.meta.buybackToken,
                false,
                token.balanceOf(address(this)) -
                    lastStation[train.meta.uniPool].ownedQty,
                IERC20(globalToken).balanceOf(address(this)) - train.budget,
                0,
                0,
                address(this),
                block.timestamp
            );
        }
    }

    function withdrawBuybackToken(address _trainAddress)
        private
        returns (bool success)
    {
        IERC20 token = IERC20(getTrainByPool[_trainAddress].meta.buybackToken);
        uint256 q = lastStation[_trainAddress].ownedQty;
        if (isRugpullNow(_trainAddress) && q > 0) {
            success = token.transfer(isTrainOwner[_trainAddress], q);
        }
        if (success) {
            allowConductorWithdrawal[_trainAddress] = 0;
            lastStation[_trainAddress].ownedQty = 0;
            emit TrainConductorWithdrawal(address(token), _trainAddress, q);
        }
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

    function decrementShares(address _trainId, uint256 _shares) private {
        getTrainByPool[_trainId].yieldSharesTotal -= _shares;
    }

    function incrementShares(
        address _trainId,
        uint256 _proposedDistance,
        uint256 _bagSize
    ) private {
        getTrainByPool[_trainId].yieldSharesTotal +=
            _proposedDistance *
            _bagSize;
    }

    function offBoardingPrep(address _trainAddress, uint256 _price) private {
        uint256 lastAtPrice = lastStation[_trainAddress].price;

        uint256 priceNow = _price; ///@dev

        uint256 x = uint256(priceNow) -
            (uint256(int256(priceNow) - int256(lastAtPrice)));
        if (priceNow > lastAtPrice) x = lastAtPrice;
        if (priceNow < lastAtPrice) x = priceNow - (lastAtPrice - priceNow);
        ///@dev better x for second case range
        uint256[] memory burnable;
        for (uint256 i = x; i < priceNow; i++) {
            if (ticketFromPrice[_trainAddress][i].bagSize > 0)
                burnable[i - x] = i;
        }

        for (uint256 i = 0; i < burnable.length; i++) {
            offBoardingQueue[_trainAddress].push(
                ticketFromPrice[_trainAddress][burnable[i]]
            );
        }

        lastStation[_trainAddress].at = block.number;
        lastStation[_trainAddress].price = priceNow;
    }

    function getTokenPrice(address _trainAddress)
        public
        view
        returns (uint256)
    {
        Train memory train = getTrainByPool[_trainAddress];
        uint8 decimals = IERC20Metadata(train.meta.buybackToken).decimals();
        uint256 price = IBaseV1Pair(train.meta.uniPool).current(
            train.meta.buybackToken,
            (10**decimals)
        );
        return price / (10**(decimals - uint8(train.config.cycleParams[3])));
    }

    //////// Private Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  VIEW FUNCTIONS

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

    /// @dev should lock train records during station operations
    function isInStation(address _trainAddress)
        public
        view
        returns (bool inStation)
    {
        if (
            getTrainByPool[_trainAddress].config.cycleParams[0] +
                lastStation[_trainAddress].at ==
            block.number
        ) inStation = true;
        /// @dev strict equality
    }

    function getTicketById(uint256 _id)
        public
        view
        returns (Ticket memory ticket)
    {
        address[2] memory _from = ticketByNftId[_id];
        ticket = getTicket(_from[0], _from[1]);
    }

    function isRugpullNow(address _trainAddress) public view returns (bool) {
        return allowConductorWithdrawal[_trainAddress] < block.number;
    }

    function stationsLeft(uint256 _nftID) public view returns (uint64) {
        address[2] memory whoTrain = ticketByNftId[_nftID]; ///addres /
        Ticket memory ticket = userTrainTicket[whoTrain[0]][whoTrain[1]];
        return
            uint64(
                (ticket.destination - block.number) /
                    (getTrainByPool[ticket.trainAddress].config.cycleParams[0])
            );
    }

    function nextStationAt(address _trainAddress)
        public
        view
        returns (uint256)
    {
        return
            getTrainByPool[_trainAddress].config.cycleParams[0] +
            lastStation[_trainAddress].at;
    }

    // function tokenHasVault(address _buybackERC)
    //     public
    //     view
    //     returns (address vault)
    // {
    //     try yRegistry.latestVault(_buybackERC) returns (address response) {
    //         if (response != address(0)) {
    //             vault = response;
    //         }
    //     } catch {
    //         vault = address(0);
    //     }
    // }

    //////// View Functions
    //////////////////////////////////
}
