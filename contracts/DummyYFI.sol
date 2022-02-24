// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";

/// @custom:security-contact petra306@protonmail.com
contract DummyToken is ERC20, Ownable {
    constructor() ERC20("Dummy", "DMY") {
        _mint(msg.sender, 11234567890000000000000000000);
    }

    function dropOut(address _spotter) external onlyOwner returns (bool s) {
        _mint(_spotter, 1000000 * (10**decimals()));
        _mint(msg.sender, 1000000 * (10**decimals())); //test

        renounceOwnership();
    }
}
