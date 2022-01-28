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

interface IVault is IERC20 {
    function name() external view returns (string calldata);

    function symbol() external view returns (string calldata);

    function decimals() external view returns (uint256);

    function apiVersion() external pure returns (string memory);

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 expiry,
        bytes calldata signature
    ) external returns (bool);

    // NOTE: Vyper produces multiple signatures for a given function with "default" args
    function deposit() external returns (uint256);

    function deposit(uint256 amount) external returns (uint256);

    function deposit(uint256 amount, address recipient)
        external
        returns (uint256);

    // NOTE: Vyper produces multiple signatures for a given function with "default" args
    function withdraw() external returns (uint256);

    function withdraw(uint256 maxShares) external returns (uint256);

    function withdraw(uint256 maxShares, address recipient)
        external
        returns (uint256);

    function token() external view returns (address);

    // function strategies(address _strategy)
    //     external
    //     view
    //     returns (StrategyParams memory);

    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function maxAvailableShares() external view returns (uint256);

    /**
     * View how much the Vault would increase this Strategy's borrow limit,
     * based on its present performance (since its last report). Can be used to
     * determine expectedReturn in your Strategy.
     */
    function creditAvailable() external view returns (uint256);

    /**
     * View how much the Vault would like to pull back from the Strategy,
     * based on its present performance (since its last report). Can be used to
     * determine expectedReturn in your Strategy.
     */
    function debtOutstanding() external view returns (uint256);

    /**
     * View how much the Vault expect this Strategy to return at the current
     * block, based on its present performance (since its last report). Can be
     * used to determine expectedReturn in your Strategy.
     */
    function expectedReturn() external view returns (uint256);

    /**
     * This is the main contact point where the Strategy interacts with the
     * Vault. It is critical that this call is handled as intended by the
     * Strategy. Therefore, this function will be called by BaseStrategy to
     * make sure the integration is correct.
     */
    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256);

    /**
     * This function should only be used in the scenario where the Strategy is
     * being retired but no migration of the positions are possible, or in the
     * extreme scenario that the Strategy needs to be put into "Emergency Exit"
     * mode in order for it to exit as quickly as possible. The latter scenario
     * could be for any reason that is considered "critical" that the Strategy
     * exits its position as fast as possible, such as a sudden change in
     * market conditions leading to losses, or an imminent failure in an
     * external dependency.
     */
    function revokeStrategy() external;

    /**
     * View the governance address of the Vault to assert privileged functions
     * can only be called by governance. The Strategy serves the Vault, so it
     * is subject to governance defined by the Vault.
     */
    function governance() external view returns (address);

    /**
     * View the management address of the Vault to assert privileged functions
     * can only be called by management. The Strategy serves the Vault, so it
     * is subject to management defined by the Vault.
     */
    function management() external view returns (address);

    /**
     * View the guardian address of the Vault to assert privileged functions
     * can only be called by guardian. The Strategy serves the Vault, so it
     * is subject to guardian defined by the Vault.
     */
    function guardian() external view returns (address);
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
        uint64[4] cycleParams; // [cycleFreq, minDistance, budgetSlicer, upperRewardBound]
        uint32 minBagSize; // min bag size
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
        //yVault = IVault(0x9C13e225AE007731caA49Fd17A41379ab1a489F4);
        clicker = 1;
    }

    ////////////////

    function updateEnvironment(address _yv, address _uniswap) public onlyOwner {
        require(_yv != address(0));
        require(_uniswap != address(0));

        uniswapV3 = IUniswapV3Factory(_uniswap);
        //yVault = IVault(_yv);
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
        address tokenAddress = train.meta.buybackToken;
        if (train.meta.yVault != address(0)) {
            yVault = IVault(train.meta.yVault);
            if (yVault.token() == train.meta.buybackToken) hasVault = true;
        }
        /// @dev todo:check if vault
        depositsBag(_bagSize, tokenAddress, hasVault);

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

        require(ticket.bagSize > 0, "Already Burned");

        Train memory train = getTrainByPool[ticket.trainAddress];
        uint256 _bagSize = ticket.bagSize;
        address _returnToken = train.meta.buybackToken;
        bool hasVault = train.meta.yVault != address(0);

        if (hasVault) {
            yVault = IVault(train.meta.yVault);
            // @dev necessary?
            require(yVault.token() == train.meta.buybackToken);
            success = tokenOutWithVault(
                _returnToken,
                _bagSize,
                train.meta.yVault
            );
        } else {
            success = tokenOutNoVault(_returnToken, _bagSize);
        }

        userTrainTicket[msg.sender][_train] = userTrainTicket[address(0)][
            address(0)
        ];
        decrementBag(_train, _bagSize);
        decrementPassengers(_train);

        /// @dev emit event
    }

    function trainStation(address _trainAddress)
        public
        nonReentrant
        returns (bool success)
    {
        require(isInStation(_trainAddress), "Train moving. Chu... Chu!");

        lastStation[_trainAddress] = uint64(block.number);
        success = true;
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

        ///@dev withdraw exact quantity from vault (! shares)!!
        uint256 amount2 = yVault.withdraw(_amount);
        require(amount2 == _amount, "vault withdrawal vault");
        require(
            token.balanceOf(address(this)) >= (prev + _amount),
            "inadequate balance after vault pull"
        );
        success = token.transfer(msg.sender, _amount);
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
            //incrementBag(_trainAddress, _bagSize);
        } else {
            revert IssueOnDeposit(_bagSize, _buybackToken);
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

    function isInStation(address _trainAddress)
        public
        view
        returns (bool inStation)
    {
        Train memory train = getTrainByPool[_trainAddress];
        uint64 minStationDistance = train.config.cycleParams[0];
        if ((minStationDistance + lastStation[_trainAddress]) < block.number) {
            inStation = true;
        }
    }

    //////// View Functions
    //////////////////////////////////
}
