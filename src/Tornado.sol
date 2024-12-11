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

import "./MerkleTreeWithHistory.sol";
import "./utils/ReentrancyGuard.sol";

interface IVerifier {
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[8] calldata _pubSignals
    ) external view returns (bool);
}

interface IPoseidonHasher {
    function poseidon(uint256[3] calldata) external pure returns (uint256);
}

abstract contract Tornado is MerkleTreeWithHistory, ReentrancyGuard {
    IVerifier public immutable verifier;
    IPoseidonHasher public immutable poseidonHasher;
    uint256 public denomination;

    mapping(bytes32 => bool) public nullifierHashes;
    // we store all commitments just to prevent accidental deposits with the same commitment
    mapping(bytes32 => bool) public commitments;

    event Deposit(uint256 indexed commitment, uint32 leafIndex, uint256 timestamp);
    event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee);

    /**
     * @dev The constructor
     * @param _verifier the address of SNARK verifier for this contract
     * @param _mimcHasher the address of MiMC hash contract
     * @param _poseidonHasher the address of Poseidon hash contract
     * @param _denomination transfer amount for each deposit
     * @param _merkleTreeHeight the height of deposits' Merkle Tree
     */
    constructor(IVerifier _verifier, IHasher _mimcHasher, IPoseidonHasher _poseidonHasher, uint256 _denomination, uint32 _merkleTreeHeight)
        MerkleTreeWithHistory(_merkleTreeHeight, _mimcHasher)
    {
        require(_denomination > 0, "denomination should be greater than 0");
        verifier = _verifier;
        denomination = _denomination;
        poseidonHasher = _poseidonHasher;
    }

    /**
     * @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
     * @param _commitmentWithoutAmount the note commitment, which is PoseidonHash(amount, depositAddress, PoseidonHash(nullifier + secret))
     */
    function deposit(uint256 _commitmentWithoutAmount) external payable nonReentrant {
        uint256 _amount = msg.value;
        uint256 _commitment = poseidonHasher.poseidon([_amount, uint256(uint160(msg.sender)), _commitmentWithoutAmount]);

        uint32 insertedIndex = _insert(bytes32(_commitment));
        commitments[bytes32(_commitment)] = true;
        _processDeposit();

        emit Deposit(_commitment, insertedIndex, block.timestamp);
    }

    /**
     * @dev this function is defined in a child contract
     */
    function _processDeposit() internal virtual;

    /**
     * @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
     * `input` array consists of:
     *   - merkle root of all deposits in the contract
     *   - hash of unique deposit nullifier to prevent double spends
     *   - the recipient of funds
     *   - optional fee that goes to the transaction sender (usually a relay)
     */
    function withdraw(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        bytes32 _root,
        bytes32 _nullifierHash,
        address _recipient,
        address _relayer,
        uint256 _fee,
        uint256 _amount,
        uint256 _newCommitment,
        uint256 _refund
    ) external payable nonReentrant {
        require(_fee <= denomination, "Fee exceeds transfer value");
        require(!nullifierHashes[_nullifierHash], "The note has been already spent");
        require(isKnownRoot(_root), "Cannot find your merkle root"); // Make sure to use a recent one
        require(
            verifier.verifyProof(
                _pA,
                _pB,
                _pC,
                [
                    uint256(_root),
                    uint256(_nullifierHash),
                    uint256(uint160(_recipient)),
                    uint256(uint160(_relayer)),
                    _fee,
                    _amount,
                    _newCommitment,
                    _refund
                ]
            ),
            "Invalid withdraw proof"
        );

        nullifierHashes[_nullifierHash] = true;
        _processWithdraw(_recipient, _relayer, _fee, _refund, _amount);
        emit Withdrawal(_recipient, _nullifierHash, _relayer, _fee);
    }

    /**
     * @dev this function is defined in a child contract
     */
    function _processWithdraw(address _recipient, address _relayer, uint256 _fee, uint256 _refund, uint256 _amount) internal virtual;

    /**
     * @dev whether a note is already spent
     */
    function isSpent(bytes32 _nullifierHash) public view returns (bool) {
        return nullifierHashes[_nullifierHash];
    }

    /**
     * @dev whether an array of notes is already spent
     */
    function isSpentArray(bytes32[] calldata _nullifierHashes) external view returns (bool[] memory spent) {
        spent = new bool[](_nullifierHashes.length);
        for (uint256 i = 0; i < _nullifierHashes.length; i++) {
            if (isSpent(_nullifierHashes[i])) {
                spent[i] = true;
            }
        }
    }
}
