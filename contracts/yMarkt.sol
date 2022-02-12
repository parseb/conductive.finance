//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20Metadata.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/token/ERC721/ERC721.sol";

import "./UniswapInterfaces.sol";
import "./ITrainSpotting.sol";

contract Conductive is
    ERC721("conductive.finance", "Train"),
    Ownable,
    ReentrancyGuard,
    ITrainSpotting
{
    uint256 clicker;
    //Ticket[] public allTickets;
    //Train[] public allTrains;

    mapping(address => Ticket[]) public offBoardingQueue;

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

    IUniswapV2Factory baseFactory;
    IUniswapV2Router02 solidRouter;
    ITrainSpotting Spotter;

    /// @dev reduced surface
    address globalToken;

    constructor(address _factory, address _SpotterAddress) {
        baseFactory = IUniswapV2Factory(_factory);

        Spotter = ITrainSpotting(_SpotterAddress);
        (address solid, address token) = Spotter._spottingParams(
            address(0),
            address(this),
            address(0)
        );

        solidRouter = IUniswapV2Router02(solid);
        globalToken = token;
        clicker = 1;
    }

    // function init() public returns (bool s) {
    //     s = _SpottingParams(globalToken, address(this), address(solidRouter));
    // }

    function updatesEnvironment(
        address _factory,
        address _router,
        address _gDenom
    ) external onlyOwner returns (bool) {
        require(
            _factory != address(0) &&
                _router != address(0) &&
                _gDenom != address(0)
        );

        baseFactory = IUniswapV2Factory(_factory);
        solidRouter = IUniswapV2Router02(_router);

        emit RailNetworkChanged(address(baseFactory), _factory);
    }

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

    event RailNetworkChanged(address indexed _from, address indexed _to);

    event TrainParamsChanged(
        address indexed _trainAddress,
        uint64[4] _newParams
    );

    event TrainStarted(address _trainAddress, Train _train);

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

    // modifier onlyExpiredTickets(address _train) {
    //     require(
    //         userTrainTicket[msg.sender][_train].destination < block.number,
    //         "Train is Moving"
    //     );
    //     _;
    // }

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

    /// fallback
    fallback() external {
        emit FallbackCall(msg.sender, msg.data);
    }

    receive() external payable {
        (bool s, ) = payable(owner()).call{value: msg.value}("on purple");
        if (!s) {
            emit FallbackCall(msg.sender, msg.data);
        }
    }

    ////////////////////////////////

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
        uint256 _initialBudget,
        bool _levers
    ) public zeroNotAllowed(_cycleParams) returns (bool successCreated) {
        require(_cycleParams[0] > 10); //@dev mincycle hardcoded for jump
        require(_cycleParams[2] > 1 && _cycleParams[2] < 100);

        address uniPool = baseFactory.getPair(_buybackToken, globalToken);
        if (uniPool == address(0)) {
            uniPool = baseFactory.createPair(_buybackToken, globalToken);
        }

        require(uniPool != address(0));
        //trainAddressVault[uniPool] = IVault(tokenHasVault(_buybackToken));
        require(getTrainByPool[uniPool].meta.uniPool == address(0), "exists");

        if (_initialBudget > 0)
            require(
                IERC20(globalToken).transferFrom(
                    msg.sender,
                    address(this),
                    _initialBudget
                )
            );

        Train memory _train = Train({
            meta: operators({buybackToken: _buybackToken, uniPool: uniPool}),
            yieldSharesTotal: 0,
            passengers: 0,
            budget: _initialBudget,
            inCustody: 0,
            config: configdata({
                cycleParams: _cycleParams,
                minBagSize: _minBagSize,
                controlledSpeed: _levers
            })
        });

        getTrainByPool[uniPool] = _train;
        isTrainOwner[uniPool] = msg.sender;
        // lastStation[uniPool].at = block.number;

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
        uint256 minPrice = 10**(18 - train.config.cycleParams[3]);
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
        //allTickets.push(ticket);

        getTrainByPool[_trainAddress].passengers += 1;
        getTrainByPool[_trainAddress].inCustody += _bagSize;
        getTrainByPool[_trainAddress].yieldSharesTotal +=
            _bagSize *
            (_stations * train.config.cycleParams[0]);

        clicker++;

        success = true;
        emit TicketCreated(msg.sender, _trainAddress, ticket.perUnit);
    }

    /// tear gas war
    function trainStation(address _trainAddress) public returns (bool s) {
        uint256 g1 = gasleft();
        require(isInStation(_trainAddress), "Train moving. (Chu, Chu)");
        stationData memory prevStation = Spotter._getLastStation(_trainAddress);
        require(prevStation.at != block.number, "Departing");

        Train memory train = getTrainByPool[_trainAddress];
        uint256 _price = IUniswapV2Pair(train.meta.uniPool)
            .price0CumulativeLast();

        if (prevStation.lastGas == 0) {
            solidRouter.addLiquidity(
                train.meta.buybackToken,
                globalToken,
                IERC20(train.meta.buybackToken).balanceOf(address(this)),
                train.budget,
                0,
                0,
                address(this),
                block.timestamp
            );
            emit TrainStarted(_trainAddress, train);
            return Spotter._trainStation(train, _price, g1);
        }

        solidRouter.removeLiquidity(
            train.meta.buybackToken,
            globalToken,
            IERC20(train.meta.uniPool).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );

        if (allowConductorWithdrawal[train.meta.uniPool] >= block.number) {
            Spotter._withdrawBuybackToken(
                train,
                isTrainOwner[train.meta.uniPool]
            );
            allowConductorWithdrawal[_trainAddress] = 0;
        }

        Ticket[] memory toBurnTickets = offBoardingPrep(
            _trainAddress,
            _price / (10**(18 - train.config.cycleParams[3])),
            prevStation
        );

        for (uint256 i = 0; i < toBurnTickets.length; i++) {
            Ticket memory _t = toBurnTickets[i];
            if (Spotter._offBoard(_t, train, ticketByNftId[_t.nftid][0]))
                _burn(_t.nftid);
            delete offBoardingQueue[_trainAddress][i];
        }

        s = Spotter._trainStation(train, _price, g1);
    }

    function offBoardingPrep(
        address _trainAddress,
        uint256 priceNow,
        stationData memory prevS
    ) private returns (Ticket[] memory) {
        uint256 lastAtPrice = prevS.price;

        uint256 x = uint256(priceNow) -
            (uint256(int256(priceNow) - int256(lastAtPrice)));
        if (priceNow > lastAtPrice) x = lastAtPrice;
        if (priceNow < lastAtPrice) x = priceNow - (lastAtPrice - priceNow);

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

        return offBoardingQueue[_trainAddress];
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

    function requestOffBoarding(address _trainAddress)
        public
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = userTrainTicket[msg.sender][_trainAddress];
        require(stationsLeft(ticket.nftid) <= 1, "maybe not next staton");

        offBoardingQueue[_trainAddress].push(ticket);

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

    // function addToGasBudget(address _trainAddress)
    //     public
    //     payable
    //     returns (bool)
    // {
    //     lastStation[_trainAddress].gasBudget += msg.value;
    //     return true;
    // }

    function addToTrainBudget(address _trainAddress, uint256 _amount)
        public
        payable
        returns (bool success)
    {
        require(!isInStation(_trainAddress), "please wait");
        require(
            IERC20(globalToken).transferFrom(msg.sender, address(this), _amount)
        );
        getTrainByPool[_trainAddress].budget += _amount;
        return true;
    }

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

            userTrainTicket[from][T.trainAddress] = emptyticket;
            //decrementShares(T.trainAddress, toBurn);
            getTrainByPool[T.trainAddress].yieldSharesTotal -=
                T.bagSize *
                (T.destination - T.departure);
            // decrementBag(T.trainAddress, T.bagSize);
            getTrainByPool[T.trainAddress].inCustody -= T.bagSize;
            //decrementPassengers(T.trainAddress);

            getTrainByPool[T.trainAddress].passengers -= 1;
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
            uint256 _toBurn = IERC20(train.meta.uniPool).balanceOf(
                address(this)
            ) / (train.inCustody / _amount);

            solidRouter.removeLiquidity(
                train.meta.buybackToken,
                globalToken,
                _toBurn,
                _amount,
                0,
                address(this),
                block.timestamp
            );

            success = token.transfer(msg.sender, _amount);

            // solidRouter.addLiquidity(
            //     address(token),
            //     train.meta.buybackToken,
            //     token.balanceOf(address(this)) -
            //         lastStation[train.meta.uniPool].ownedQty,
            //     IERC20(globalToken).balanceOf(address(this)) - train.budget,
            //     0,
            //     0,
            //     address(this),
            //     block.timestamp
            // );
        }
    }

    function isInStation(address _trainAddress) public view returns (bool x) {
        x = Spotter._isInStation(
            getTrainByPool[_trainAddress].config.cycleParams[0],
            getTrainByPool[_trainAddress].meta.uniPool
        );
    }

    // function incrementPassengers(address _trainId) private {
    //     getTrainByPool[_trainId].passengers++;
    // }

    // function decrementPassengers(address _trainId) private {
    //     getTrainByPool[_trainId].passengers--;
    // }

    // function incrementBag(address _trainId, uint256 _bagSize) private {
    //     getTrainByPool[_trainId].inCustody += _bagSize;
    // }

    // function decrementBag(address _trainId, uint256 _bagSize) private {
    //     getTrainByPool[_trainId].inCustody -= _bagSize;
    // }

    // function decrementShares(address _trainId, uint256 _shares) private {
    //     getTrainByPool[_trainId].yieldSharesTotal -= _shares;
    // }

    // function incrementShares(
    //     address _trainId,
    //     uint256 _proposedDistance,
    //     uint256 _bagSize
    // ) private {
    //     getTrainByPool[_trainId].yieldSharesTotal +=
    //         _proposedDistance *
    //         _bagSize;
    // }

    // function getTokenPrice(address _trainAddress)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     Train memory train = getTrainByPool[_trainAddress];
    //     uint8 decimals = IERC20Metadata(train.meta.buybackToken).decimals();
    //     uint256 price = IUniswapV2Pair(train.meta.uniPool)
    //         .price0CumulativeLast();
    //     return price / (10**(decimals - uint8(train.config.cycleParams[3])));
    // }

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

    function getTicketById(uint256 _id)
        public
        view
        returns (Ticket memory ticket)
    {
        address[2] memory _from = ticketByNftId[_id];
        ticket = getTicket(_from[0], _from[1]);
    }

    // function isRugpullNow(address _trainAddress) public view returns (bool) {
    //     return allowConductorWithdrawal[_trainAddress] < block.number;
    // }

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
            Spotter._getLastStation(_trainAddress).at;
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
