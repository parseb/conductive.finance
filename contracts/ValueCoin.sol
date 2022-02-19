// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20.sol";
import "./PullPayment.sol";

/// @custom:security-contact petra306@protonmail.com
contract ValueConduct is ERC20, Pausable, Ownable, PullPayment {
    constructor() ERC20("Value Conduct", "VC") {
        _mint(msg.sender, 1337000 * 10**decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}
