// https://tornado.cash
/*
 * d888888P                                           dP              a88888b.                   dP
 *    88                                              88             d8'   `88                   88
 *    88    .d8888b. 88d888b. 88d888b. .d8888b. .d888b88 .d8888b.    88        .d8888b. .d8888b. 88d888b.
 *    88    88'  `88 88'  `88 88'  `88 88'  `88 88'  `88 88'  `88    88        88'  `88 Y8ooooo. 88'  `88
 *    88    88.  .88 88       88    88 88.  .88 88.  .88 88.  .88 dP Y8.   .88 88.  .88       88 88    88
 *    dP    `88888P' dP       dP    dP `88888P8 `88888P8 `88888P' 88  Y88888P' `88888P8 `88888P' dP    dP
 * ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Tornado.sol";

contract ETHTornado is Tornado {
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0;

    constructor(IVerifier _verifier, IHasher _mimcHasher, IPoseidonHasher _poseidonHasher, uint256 _denomination, uint32 _merkleTreeHeight)
        Tornado(_verifier, _mimcHasher, _poseidonHasher, _denomination, _merkleTreeHeight)
    {}

    function _processDeposit() internal override {
        require(msg.value > MIN_DEPOSIT_AMOUNT, "Please send the correct amount");
    }

    function _processWithdraw(address _recipient, address _relayer, uint256 _fee, uint256 _refund, uint256 _amount) internal override {
        // sanity checks
        require(msg.value == 0, "Message value is supposed to be zero for ETH instance");
        require(_refund == 0, "Refund value is supposed to be zero for ETH instance");

        (bool success,) = _recipient.call{value: _amount - _fee}("");
        require(success, "payment to _recipient did not go thru");
        if (_fee > 0) {
            (success,) = _relayer.call{value: _fee}("");
            require(success, "payment to _relayer did not go thru");
        }
    }
}
