//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

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
    Ticket[] public allTickets;
    Train[] public allTrains;

    mapping(address => Ticket[]) public offBoardingQueue;

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
    ITrainSpotting Spotter;

    address globalToken;

    constructor(address _factory, address _SpotterAddress) {
        baseFactory = IUniswapV2Factory(_factory);

        Spotter = ITrainSpotting(_SpotterAddress);

        (, address token) = Spotter._setCentralStation(address(this));

        globalToken = token;
        clicker = 1;
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
        baseFactory = IUniswapV2Factory(_factory);
        Spotter._spottingParams(globalToken, address(this), _router);

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
        uint64[2] memory _newParams
    ) public onlyTrainOwner(_trainAddress) returns (bool) {
        require(
            _newParams[0] + _newParams[1] > 51337,
            "zero values not allowed"
        );

        Train memory train = getTrainByPool[_trainAddress];

        if (train.tokenAndPool[0] == address(0))
            revert TrainNotFound(_trainAddress);

        if (train.config.controlledSpeed) {
            train.config.cycleParams = _newParams;
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
        uint64[2] memory _revenueParams,
        bool _levers
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
                revenueParams: _revenueParams,
                minBagSize: _minBagSize,
                controlledSpeed: _levers
            })
        });

        getTrainByPool[uniPool] = _train;
        isTrainOwner[uniPool] = msg.sender;

        allTrains.push(_train);
        emit TrainCreated(uniPool, _yourToken);
        successCreated = Spotter._setStartStation(uniPool);
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
        // ticketFromPrice[_trainAddress][ticket.perUnit] = ticket;
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

    function trainStation(address _trainAddress) public returns (bool s) {
        uint256 g1 = gasleft();
        require(isInStation(_trainAddress), "Train none or moving");
        uint256[4] memory prevStation = Spotter._getLastStation(_trainAddress);
        require(prevStation[0] != block.number, "Departing");

        Train memory train = getTrainByPool[_trainAddress];
        uint256 _price = IUniswapV2Pair(_trainAddress).price0CumulativeLast();

        if (prevStation[3] == 0) {
            return Spotter._trainStation(train.tokenAndPool, [_price, g1]);
        }

        Spotter._removeAllLiquidity(train.tokenAndPool[0], _trainAddress);

        if (allowConductorWithdrawal[train.tokenAndPool[1]] >= block.number) {
            Spotter._withdrawBuybackToken(
                [
                    _trainAddress,
                    train.tokenAndPool[0],
                    isTrainOwner[_trainAddress]
                ]
            );
            allowConductorWithdrawal[_trainAddress] = 0;
        }

        s = Spotter._trainStation(train.tokenAndPool, [_price, g1]);
    }

    function burnTicket(uint256 _nftId)
        public
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = getTicketById(_nftId);
        require(ticket.burner == msg.sender, "Unauthorised");
        require(ticket.departure + 10 < block.number, "too soon");
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
            _burn(ticket.nftid);
            emit IsOut(ticket.burner, ticket.trainAddress, ticket.nftid);
        }
    }

    function assignBurner(uint128 _id, address _newBurner)
        public
        returns (bool s)
    {
        Ticket memory ticket = getTicketById(_id);
        require(ticket.burner == msg.sender, "Unauthorised");
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
        require(stationsLeft(ticket.nftid) <= 1, "maybe not next staton");
        require(ticket.burner == msg.sender, "active as collateral");
        offBoardingQueue[_trainAddress].push(ticket);

        success = true;
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
            Spotter._getLastStation(_trainAddress)[0];
    }

    //////// View Functions
    //////////////////////////////////
}
