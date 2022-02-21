//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

interface ITrainSpotting {
    function _spottingParams(
        address baseToken,
        address bossContract,
        address uniRouter
    ) external returns (address, address);

    function _trainStation(
        address[2] memory addresses,
        uint256[2] memory context
    ) external returns (bool);

    function _offBoard(uint256[6] memory params, address[3] memory addresses)
        external
        returns (bool);

    /// [ trainAddress, bToken, tOwner ]
    function _withdrawBuybackToken(address[3] memory addresses)
        external
        returns (bool);

    function _addLiquidity(
        address bToken,
        uint256 bAmout,
        uint256 dAmout
    ) external returns (bool);

    function _removeLiquidity(
        address bToken,
        uint256 bAmount,
        uint256 dAmount,
        uint256 lAmount
    ) external returns (bool);

    function _removeAllLiquidity(address bToken, address poolAddress)
        external
        returns (bool);

    function _isInStation(uint256, address) external view returns (bool);

    function _tokenOut(
        uint256 amountOut,
        uint256 inCustody,
        address poolAddr,
        address bToken,
        address toWho
    ) external returns (bool);

    function _approveToken(address bToken, address pool)
        external
        returns (bool);

    function _willTransferFrom(
        address from,
        address to,
        address token,
        uint256 value
    ) external returns (bool);

    function _setCentralStation(address centralStation)
        external
        returns (address, address);

    function _initL(address yourToken, uint256[2] memory ammounts)
        external
        returns (bool);

    function _getLastStation(address train)
        external
        view
        returns (uint256[4] memory stationD);

    function _setStartStation(address _trainAddress) external returns (bool);
}
