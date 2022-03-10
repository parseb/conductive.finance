//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact: petra306@protonmail.com

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20Metadata.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/token/ERC721/ERC721.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";

import "./UniswapInterfaces.sol";
import "./ITrainSpotting.sol";
import "./StructsDataType.sol";

contract Conductive is
    ERC721("conductive.finance", "Train Ticket"),
    Ownable,
    ReentrancyGuard
{
    uint256 clicker;
    //Ticket[] public allTickets;
    Train[] public allTrains;

    /// @notice gets Ticket of [user] for [train]
    mapping(address => mapping(address => Ticket)) userTrainTicket;

    /// @notice get Train by address
    mapping(address => Train) getTrainByPool;

    /// @notice fetch ticket from nftid [account,trainId]
    mapping(uint256 => address[2]) ticketByNftId;

    /// @notice stores train owner
    mapping(address => address) isTrainOwner;

    /// @notice true if user has requested offboarding - should prevent burner
    mapping(uint256 => bool) public requestedOffBoarding;

    /// @notice stores after what block conductor will be able to withdraw howmuch of buybacked token
    mapping(address => uint256) allowConductorWithdrawal; //[block]

    IUniswapV2Factory baseFactory;
    ITrainSpotting Spotter;

    address globalToken;
    address incomeOwner;

    constructor(address _factory, address _SpotterAddress) {
        baseFactory = IUniswapV2Factory(_factory);

        Spotter = ITrainSpotting(_SpotterAddress);

        (, address token) = Spotter._setCentralStation(address(this));
        globalToken = token;
        incomeOwner = msg.sender;
        
        clicker = 100;
    }

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

        globalToken = _gDenom;
        incomeOwner = msg.sender;
        
        baseFactory = IUniswapV2Factory(_factory);
        Spotter._spottingParams(globalToken, address(this), _router);

        emit RailNetworkChanged(address(baseFactory), _factory);
        return true;
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

    error UnavailableInStation(address _train);
    error UnauthorizedBurn(uint128 _nftId, uint128 _sender);
    //////  Errors
    ////////////////////////////////

    ////////////////////////////////
    ///////  EVENTS

    event FallbackCall(address _sender);

    event TrainCreated(
        address indexed _trainAddress,
        address indexed _yourToken
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

    event IsOut(
        address indexed _who,
        address indexed _ofTrain,
        uint256 indexed _nftID
    );

    event TrainConductorBeingWeird(
        address indexed train,
        address indexed conductor
    );

    event RailNetworkChanged(address indexed _from, address indexed _to);

    event TrainParamsChanged(
        address indexed _trainAddress,
        uint64[2] _newParams
    );

    event TrainOwnerChanged(
        address indexed _trainAddress,
        address indexed _oldOwner,
        address _newOwner
    );

    event ChangedBurnerOf(
        uint128 _nftId,
        address indexed _newBurner,
        address indexed _oldBurner
    );

    //////  Events
    ////////////////////////////////

    ////////////////////////////////
    ////////  MODIFIERS

    // modifier zeroNotAllowed(uint64[4] memory _params) {
    //     for (uint8 i = 0; i < 4; i++) {
    //         if (_params[i] < 1) revert ZeroValuesNotAllowed();
    //     }
    //     _;
    // }

    modifier onlyTrainOwner(address _train) {
        if (!(isTrainOwner[_train] == msg.sender))
            revert NotTrainOwnerError(_train, msg.sender);
        _;
    }

    ///////// Modifiers
    //////////////////////////////

    /// fallback
    // fallback() external {
    //     emit FallbackCall(msg.sender);
    // }

    // receive() external payable {
    //     (bool s, ) = payable(owner()).call{value: msg.value}("on purple");
    //     if (!s) {
    //         emit FallbackCall(msg.sender);
    //     }
    // }

    ////////////////////////////////

    function changeTrainParams(
        address _trainAddress,
        uint64[2] memory _newParams,
        uint64[2] memory _newParamsRev,
        bool[2] memory _control
    ) public onlyTrainOwner(_trainAddress) nonReentrant returns (bool) {
        require(
            _newParams[0] + _newParams[1] > 51337,
            "zero values not allowed"
        );

        Train memory train = getTrainByPool[_trainAddress];

        if (train.tokenAndPool[0] == address(0))
            revert TrainNotFound(_trainAddress);

        if (train.config.control[0]) {
            train.config.cycleParams = _newParams;
            train.config.control = _control;
            getTrainByPool[_trainAddress] = train;
            allowConductorWithdrawal[_trainAddress] = 0;
            emit TrainParamsChanged(_trainAddress, _newParams);
            return true;
        } else {
            revert("Immutable Train");
        }
    }

    function changeTrainOwner(address _trainAddress, address _newOwner)
        public
        onlyTrainOwner(_trainAddress)
        returns (bool)
    {
        isTrainOwner[_trainAddress] = _newOwner;
        emit TrainOwnerChanged(_trainAddress, msg.sender, _newOwner);
        return true;
    }

    ///////   Modifiers
    /////////////////////////////////

    /////////////////////////////////
    ////////  PUBLIC FUNCTIONS

    function createTrain(
        address _yourToken,
        uint64[2] memory _cycleParams,
        uint128 _minBagSize,
        uint256[2] memory _initLiquidity,
        bool[2] memory _levers
    ) public nonReentrant returns (bool successCreated) {
        require((_cycleParams[0] > 1337) && (_cycleParams[1] > 2)); //min stations/day ticket

        address uniPool = baseFactory.getPair(_yourToken, globalToken);
        if (uniPool == address(0)) {
            uniPool = baseFactory.createPair(_yourToken, globalToken);
            if ((_initLiquidity[0] / 2) + (_initLiquidity[1] / 2) > 2) {
                Spotter._approveToken(_yourToken, uniPool);
                IERC20(_yourToken).transferFrom(
                    msg.sender,
                    address(Spotter),
                    _initLiquidity[0]
                );
                IERC20(globalToken).transferFrom(
                    msg.sender,
                    address(Spotter),
                    _initLiquidity[1]
                );
                require(
                    Spotter._initL(_yourToken, _initLiquidity),
                    "liquidity not added"
                );
            }
        }

        require(
            uniPool != address(0) &&
                getTrainByPool[uniPool].tokenAndPool[1] == address(0),
            "exists or no pool"
        );

        Train memory _train = Train({
            tokenAndPool: [_yourToken, uniPool],
            yieldSharesTotal: 0,
            passengers: 0,
            inCustody: 0,
            config: configdata({
                cycleParams: _cycleParams,
                minBagSize: _minBagSize,
                control: _levers
            })
        });

        getTrainByPool[uniPool] = _train;
        isTrainOwner[uniPool] = msg.sender;

        allTrains.push(_train);
        emit TrainCreated(uniPool, _yourToken);
        successCreated = Spotter._setStartStation(uniPool, _yourToken, _initLiquidity[0]);
    }

    function createTicket(
        uint64 _stations, // how many cycles
        uint256 _perUnit, // target price
        address _trainAddress, // train address
        uint256 _bagSize // nr of tokens
    ) public nonReentrant returns (bool success) {
        // if (!isInStation(_trainAddress))
        //     revert UnavailableInStation(_trainAddress);
        if (userTrainTicket[msg.sender][_trainAddress].destination > 0)
            revert AlreadyOnThisTrain(_trainAddress);

        if (
            _stations == 0 ||
            _bagSize == 0 ||
            _perUnit == 0 ||
            _trainAddress == address(0)
        ) {
            revert ZeroValuesNotAllowed();
        }

        Train memory train = getTrainByPool[_trainAddress];
        if (train.tokenAndPool[0] == address(0))
            revert TrainNotFound(_trainAddress);
        if (_bagSize < train.config.minBagSize)
            revert MinDepositRequired(train.config.minBagSize, _bagSize);

        bool transfer = Spotter._willTransferFrom(
            msg.sender,
            address(Spotter),
            train.tokenAndPool[0],
            _bagSize
        );

        if (!transfer)
            revert IssueOnDeposit(_bagSize, address(train.tokenAndPool[0]));

        Ticket memory ticket = Ticket({
            destination: uint256(_stations * train.config.cycleParams[0]) +
                block.number,
            departure: block.number,
            bagSize: _bagSize,
            perUnit: _perUnit,
            trainAddress: _trainAddress,
            nftid: clicker,
            burner: msg.sender
        });

        _safeMint(msg.sender, clicker);

        userTrainTicket[msg.sender][_trainAddress] = ticket;
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

    function trainStation(address _trainAddress)
        public
        nonReentrant
        returns (bool s)
    {
        require(isInStation(_trainAddress), "Train none or moving");
        require(Spotter._ensureNoDoubleEntry(_trainAddress), "Departing");

        Train memory train = getTrainByPool[_trainAddress];

        Spotter._removeAllLiquidity(train.tokenAndPool[0], _trainAddress);
        uint256 price = Spotter._getPrice(
            train.tokenAndPool[0],
            train.tokenAndPool[1]
        );
        // inCustody, yieldSharesTotal, bToken

        if (allowConductorWithdrawal[train.tokenAndPool[1]] >= block.number) {
            allowConductorWithdrawal[_trainAddress] = 0;

            require(
                Spotter._withdrawBuybackToken(
                    [
                        _trainAddress,
                        train.tokenAndPool[0],
                        isTrainOwner[_trainAddress]
                    ]
                ),
                "Conductor Withdrawal Failed"
            );
        }
        //inCustody, yieldSharesTotal, bToken = 0;
        uint256[] memory toBurn = Spotter._trainStation(
            train.tokenAndPool,
            train.inCustody,
            train.yieldSharesTotal,
            price
        );

        for (uint256 i = 0; i < toBurn.length; i++) {
            _burn(toBurn[i]);
        }
    }

    function burnTicket(uint256 _nftId)
        public
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = getTicketById(_nftId);
        require(ticket.burner == msg.sender, "Unauthorised");
        require(ticket.departure + 10 < block.number, "unspent delay");
        require(!requestedOffBoarding[_nftId], "offboarding in progress");
        Train memory train = getTrainByPool[ticket.trainAddress];
        // uint256 amountOut, uint256 inCustody, address poolAddr, address bToken
        success = Spotter._tokenOut(
            ticket.bagSize,
            train.inCustody,
            ticket.trainAddress,
            train.tokenAndPool[0],
            ticket.burner
        );
        if (success) {
            /// x - valid shares
            uint256 x = ticket.destination > block.number ? (block.number - ticket.departure) * ticket.bagSize 
            : (ticket.destination - ticket.departure) * ticket.bagSize;
            /// x - correspondign % lp token
            x = (IERC20(train.tokenAndPool[1]).balanceOf(address(Spotter)) / train.yieldSharesTotal) * x;
            
            /// create spotter function to approve x LP tp incomeOwner
            Spotter._approveOwnerLP(incomeOwner, x, train.tokenAndPool[1]);

            _burn(ticket.nftid);
            emit IsOut(ticket.burner, ticket.trainAddress, ticket.nftid);
        }
    }

    function assignBurner(uint128 _id, address _newBurner)
        public
        nonReentrant
        returns (bool s)
    {
        Ticket memory ticket = getTicketById(_id);
        require(ticket.burner == msg.sender, "Unauthorised");
        require(!requestedOffBoarding[_id]);
        ticket.burner = _newBurner;

        userTrainTicket[ticketByNftId[_id][0]][ticketByNftId[_id][1]] = ticket;

        s = true;
        emit ChangedBurnerOf(_id, _newBurner, ticketByNftId[_id][1]);
    }

    function requestOffBoarding(address _trainAddress)
        public
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = userTrainTicket[msg.sender][_trainAddress];
        require(ticket.burner == msg.sender, "active as collateral");
        if (ticket.destination > block.number)
            require(
                ((ticket.destination - block.number) /
                    getTrainByPool[_trainAddress].config.cycleParams[0]) <= 1,
                "maybe not next station"
            );

        require(!requestedOffBoarding[ticket.nftid]);
        requestedOffBoarding[ticket.nftid] = true;
        success = Spotter._addToOffboardingList(ticket.nftid, _trainAddress);
    }

    /// @notice announces withdrawal intention
    /// @dev rugpulling timelock intention
    function conductorWithdrawal(uint64 _wen, address _trainAddress)
        public
        onlyTrainOwner(_trainAddress)
    {
        if (!isInStation(_trainAddress))
            revert UnavailableInStation(_trainAddress);

        /// @dev irrelevant if cyclelength is changeable
        require(_wen > 1, "never, cool");

        allowConductorWithdrawal[_trainAddress] =
            block.number +
            (getTrainByPool[_trainAddress].config.cycleParams[0] * _wen);

        emit TrainConductorBeingWeird(_trainAddress, msg.sender);
    }

    ///////##########
    /// dev: entertain frontrunning negatives
    function flagTicket(uint256 _nftId, uint256 _atPrice)
        public
        returns (bool s)
    {
        require(!requestedOffBoarding[_nftId], "Offboarding status");
        s = Spotter._flagTicket(_nftId, _atPrice, msg.sender);
    }

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
        if (from != address(0) && to != address(0)) revert("NonTransferable");
        if ( to == address(0)) {
            Ticket memory emptyticket;
            Ticket memory T = getTicketById(tokenId);

            userTrainTicket[from][T.trainAddress] = emptyticket;

            getTrainByPool[T.trainAddress].yieldSharesTotal -=
                T.bagSize *
                (T.destination - T.departure);

            getTrainByPool[T.trainAddress].inCustody -= T.bagSize;

            getTrainByPool[T.trainAddress].passengers -= 1;
            ticketByNftId[T.nftid] = [address(0), address(0)];
        }
    }

    ////////  Internal Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  PRIVATE FUNCTIONS

    function isInStation(address _trainAddress) public view returns (bool x) {
        x = Spotter._isInStation(
            getTrainByPool[_trainAddress].config.cycleParams[0],
            _trainAddress
        );
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

    function getTicketById(uint256 _id)
        public
        view
        returns (Ticket memory ticket)
    {
        ticket = getTicket(ticketByNftId[_id][0], ticketByNftId[_id][1]);
    }

    // function isRugpullNow(address _trainAddress) public view returns (bool) {
    //     return allowConductorWithdrawal[_trainAddress] < block.number;
    // }

    function stationsLeft(uint256 _nftID) public view returns (uint256 x) {
        Ticket memory ticket = userTrainTicket[ticketByNftId[_nftID][0]][
            ticketByNftId[_nftID][1]
        ];
        if (ticket.destination < block.number) {
            x = 0;
        } else {
            x =
                (ticket.destination - block.number) /
                getTrainByPool[ticket.trainAddress].config.cycleParams[0];
        }
    }

    function nextStationAt(address _trainAddress)
        public
        view
        returns (uint256)
    {
        return
            getTrainByPool[_trainAddress].config.cycleParams[0] +
            Spotter._getLastStation(_trainAddress)[0];
    }

    function getFlaggedQueue(address _trainAddress)
        public
        view
        returns (uint256[] memory q)
    {
        q = Spotter._getFlaggedQueue(_trainAddress);
    }

    function getOffboardingQueue(address _trainAddress)
        public
        view
        returns (uint256[] memory q)
    {
        q = Spotter._getOffboardingQueue(_trainAddress);
    }

    //////// View Functions
    //////////////////////////////////
}
