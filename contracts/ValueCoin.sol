// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";

/// @custom:security-contact petra306@protonmail.com
contract ValueConduct is ERC20, Ownable {
    constructor() ERC20("Value Conduct", "VC") {}

    function dropOut(
        address _spotter,
        address[] memory dropTo,
        uint256[] memory dropAmount
    ) external onlyOwner returns (bool s) {
        _mint(_spotter, 1000000 * (10**decimals()));
        _mint(msg.sender, 1000000 * (10**decimals())); //test

        for (uint256 i = 0; i < dropTo.length; i++) {
            _mint(dropTo[i], dropAmount[i]);
        }
        renounceOwnership();
    }
}
