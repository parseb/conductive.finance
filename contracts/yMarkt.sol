//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/// @security development only
/// @security contact:@parseb

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/access/Ownable.sol";
import "Uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "Uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";

import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/interfaces/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.4.2/contracts/token/ERC721/ERC721.sol";

interface IVault {
    function token() external view returns (address);

    function underlying() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function controller() external view returns (address);

    function governance() external view returns (address);

    function getPricePerFullShare() external view returns (uint256);

    function deposit(uint256) external;

    function depositAll() external;

    function withdraw(uint256) external;

    function withdrawAll() external;
}

contract Ymarkt is Ownable, ReentrancyGuard, ERC721("Train", "Train") {
    /// @dev Uniswap V3 Factory address used to validate token pair and price

    IUniswapV3Factory uniswapV3;
    IVault yVault;
    uint256 clicker;

    struct operators {
        address denominatorToken; //quote token contract address
        address buybackToken; //buyback token contract address
        address uniPool; //address of the uniswap pool ^
        address yVault; //address of yVault if any
        bool withSeating; // issues NFT
    }

    struct configdata {
        // uint32 cycleFreq; // sleepy blocks nr of
        // uint32 minDistance; //min distance of block travel for reward
        // uint16 budgetSlicer; // spent per cycle % (0 - 10000 0.01%-100%)
        // uint16 upperRewardBound; // upper reward bound determiner
        uint32 minBagSize; // min bag size
        uint64[4] cycleParams; // [cycleFreq, minDistance, budgetSlicer, upperRewardBound]
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
        uint64 destination; //promises to travel to block
        uint64 departure; // created on block
        uint32 rewarded; //number of times in reward space
        uint256 bagSize; //amount token
        uint256 perUnit; //buyout price
        address trainAddress; //train ID (pair pool)
        uint256 nftid; //nft id
    }

    /// @notice gets Ticket of [user] for [train]
    mapping(address => mapping(address => Ticket)) userTrainTicket;

    /// @notice get Train by address
    mapping(address => Train) getTrainByPool;

    /// @notice when last cycle was run for pool
    mapping(address => uint64) lastStation;

    /// @notice tickets fetchable by perunit price
    mapping(address => mapping(uint256 => Ticket[])) ticketsFromPrice;

    constructor() {
        uniswapV3 = IUniswapV3Factory(
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );
        yVault = IVault(0x9C13e225AE007731caA49Fd17A41379ab1a489F4);
        clicker = 1;
    }

    ////////////////

    function updateEnvironment(address _yv, address _uniswap) public onlyOwner {
        require(_yv != address(0));
        require(_uniswap != address(0));

        uniswapV3 = IUniswapV3Factory(_uniswap);
        yVault = IVault(_yv);
    }

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

    event DepositNoVault(uint256 amount, address token);

    //////  Events
    ////////////////////////////////

    //////XXXXX ERC721
    /////XXXXX  deposit at cycle in pool.

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

    modifier zeroNotAllowed(uint64[4] memory _params) {
        for (uint8 i = 0; i < 4; i++) {
            if (_params[i] < 1) revert ZeroValuesNotAllowed();
        }
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
        uint64[4] memory _cycleParams,
        uint32 _minBagSize,
        bool _NFT,
        bool _levers
    ) public zeroNotAllowed(_cycleParams) returns (bool successCreated) {
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
                yVault: _yVault,
                denominatorToken: _budgetToken,
                buybackToken: _buybackToken,
                uniPool: uniPool,
                withSeating: _NFT
            }),
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

        bool hasVault;
        Train memory train = getTrainByPool[_trainAddress];

        /// @dev todo:check if vault
        if (
            train.meta.yVault != address(0) &&
            yVault.underlying() == train.meta.buybackToken
        ) hasVault = true;

        if (_bagSize < train.config.minBagSize)
            revert MinDepositRequired(train.config.minBagSize, _bagSize);

        depositsBag(_bagSize, train.meta.buybackToken, hasVault);

        uint64 _departure = uint64(block.number);
        uint64 _destination = _stations *
            train.config.cycleParams[0] +
            _departure;

        Ticket memory ticket = Ticket({
            destination: _destination,
            departure: _departure,
            rewarded: 0,
            bagSize: _bagSize,
            perUnit: _perUnit,
            trainAddress: _trainAddress,
            nftid: clicker
        });

        _safeMint(msg.sender, clicker);

        userTrainTicket[msg.sender][_trainAddress] = ticket;

        incrementPassengers(_trainAddress);
        incrementBag(_trainAddress, _bagSize);

        ticketsFromPrice[_trainAddress][_perUnit].push(ticket);
        clicker++;

        ///@dev maybe pull payment wrapped token

        success = true;
    }

    function burnTicket(address _train)
        public
        onlyTicketed(_train)
        nonReentrant
        returns (bool success)
    {
        Ticket memory ticket = userTrainTicket[msg.sender][_train];
        Train memory train = getTrainByPool[ticket.trainAddress];

        uint256 _bagSize = ticket.bagSize;
        address _returnToken = train.meta.buybackToken;
        bool hasVault = train.meta.yVault != address(0);

        if (hasVault) {
            success = tokenOutNoVault(_returnToken, _bagSize);
        } else {
            success = tokenOutWithVault(
                _returnToken,
                _bagSize,
                train.meta.yVault
            );
        }

        userTrainTicket[msg.sender][_train] = userTrainTicket[address(0)][
            address(0)
        ];
        decrementBag(_train, _bagSize);
        decrementPassengers(_train);
        /// @dev emit event
    }

    //////// Public Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  INTERNAL FUNCTIONS

    function tokenOutNoVault(address _token, uint256 _amount)
        internal
        returns (bool success)
    {
        IERC20 token = IERC20(_token);
        uint256 prev = token.balanceOf(address(this));
        token.transfer(msg.sender, _amount);
        require(
            token.balanceOf(address(this)) >= (prev - _amount),
            "token transfer failed"
        );
        success = true;
    }

    function tokenOutWithVault(
        address _token,
        uint256 _amount,
        address _vault
    ) internal returns (bool success) {
        IERC20 token = IERC20(_token);

        uint256 prev = token.balanceOf(address(this));
        token.transfer(msg.sender, _amount);
        require(
            token.balanceOf(address(this)) >= (prev - _amount),
            "token transfer failed"
        );
        success = true;
    }

    ////////  Internal Functions
    /////////////////////////////////

    /////////////////////////////////
    ////////  PRIVATE FUNCTIONS

    function depositsBag(
        uint256 _bagSize,
        address _buybackToken,
        bool _hasVault
    ) private returns (bool success) {
        IERC20 token = IERC20(_buybackToken);

        uint256 _prevBalance = token.balanceOf(address(this));
        bool one = token.transferFrom(msg.sender, address(this), _bagSize);
        uint256 _currentBalance = token.balanceOf(address(this));
        bool two = _currentBalance >= (_prevBalance + _bagSize);
        if (one && two) {
            success = true;
        } else {
            revert IssueOnDeposit(_bagSize, _buybackToken);
        }

        if (_hasVault) {
            token.approve(yVault.token(), _bagSize);
            yVault.depositAll();
            require(
                _currentBalance > token.balanceOf(address(this)),
                "vault deposit failed"
            );
        } else {
            /// @dev since vaults cannot be created, deposit for yield... somewhere.
            emit DepositNoVault(_bagSize, _buybackToken);
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
