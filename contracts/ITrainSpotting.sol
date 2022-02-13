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
        uint256[5] memory context
    ) external returns (bool);

    function _offBoard(uint256[6] memory params, address[3] memory addresses)
        external
        returns (bool);

    /// [ trainAddress, bToken, tOwner ]
    function _withdrawBuybackToken(address[3] memory addresses)
        external
        returns (bool);

    function _getLastStation(address _train)
        external
        view
        returns (uint256[4] memory stationD);

    function _isInStation(uint256, address) external view returns (bool);
}
