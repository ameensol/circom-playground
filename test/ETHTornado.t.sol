// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Groth16Verifier} from "src/Verifier.sol";
import {ETHTornado, IVerifier, IHasher, IPoseidonHasher} from "src/ETHTornado.sol";

// TODO
// 1. include OG_COMMITMENT in the commitment scheme - enforce new commitment also has it
// 1.1. store deposit address & OG_commitment on the contract so we don't have to pass it in proofs

// 2. update fees/relayer/refund to be passed in as a hash 
/**
 * struct Request { // Validated in the proof as input
 *     address receipient; 
 *     bytes32 extraData; // Poseidon hash of fees/relayer/refund
 * }
 */


contract ETHTornadoTest is Test {
    uint256 public constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    IVerifier public verifier;
    ETHTornado public mixer;

    // Test vars
    address public recipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public relayer = address(0);
    uint256 public fee = 0;
    uint256 public refund = 0;

    function deployMimcSponge(bytes memory bytecode) public returns (address) {
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(deployedAddress) { revert(0, 0) }
        }
        return deployedAddress;
    }

    function deployPoseidon(bytes memory bytecode) public returns (address) {
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(deployedAddress) { revert(0, 0) }
        }
        return deployedAddress;
    }

    function setUp() public {
        // Deploy MimcSponge hasher contract.
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "forge-ffi-scripts/deployMimcsponge.js";

        bytes memory mimcspongeBytecode = vm.ffi(inputs);

        address mimcHasher;
        assembly {
            mimcHasher := create(0, add(mimcspongeBytecode, 0x20), mload(mimcspongeBytecode))
            if iszero(mimcHasher) { revert(0, 0) }
        }

        // Deploy Poseidon hasher contract.
        string[] memory inputsPoseidon = new string[](2);
        inputsPoseidon[0] = "node";
        inputsPoseidon[1] = "forge-ffi-scripts/deployPoseidon.js";

        bytes memory poseidonBytecode = vm.ffi(inputsPoseidon);

        address poseidonHasher;
        assembly {
            poseidonHasher := create(0, add(poseidonBytecode, 0x20), mload(poseidonBytecode))
            if iszero(poseidonHasher) { revert(0, 0) }
        }

        // Deploy Groth16 verifier contract.
        verifier = IVerifier(address(new Groth16Verifier()));

        /**
         * Deploy Tornado Cash mixer
         *
         * - verifier: Groth16 verifier
         * - hasher: MiMC hasher
         * - merkleTreeHeight: 20
         */
        mixer = new ETHTornado(verifier, IHasher(mimcHasher), IPoseidonHasher(poseidonHasher), 1 ether, 20);
    }

    function _getWitnessAndProof(
        bytes32 _nullifier,
        bytes32 _secret,
        uint256 _amountCommitted,
        address _recipient,
        address _relayer,
        bytes32 _newNullifier,
        bytes32 _newSecret,
        uint256 _amountToWithdraw,
        uint256[] memory leaves
    ) internal returns (uint256[2] memory, uint256[2][2] memory, uint256[2] memory, bytes32, bytes32) {
        string[] memory inputs = new string[](13 + leaves.length);
        inputs[0] = "node";
        inputs[1] = "forge-ffi-scripts/generateWitness.js";
        inputs[2] = vm.toString(_nullifier);
        inputs[3] = vm.toString(_secret);
        inputs[4] = vm.toString(_amountCommitted);
        inputs[5] = vm.toString(_recipient);
        inputs[6] = vm.toString(_relayer);
        inputs[7] = "0"; // fee
        inputs[8] = "0"; // refund
        inputs[9] = vm.toString(_newNullifier);
        inputs[10] = vm.toString(_newSecret);
        inputs[11] = vm.toString(_amountToWithdraw);
        inputs[12] = vm.toString(address(this));
    
        for (uint256 i = 0; i < leaves.length; i++) {
            inputs[13 + i] = vm.toString(leaves[i]);
        }

        bytes memory result = vm.ffi(inputs);
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash) =
            abi.decode(result, (uint256[2], uint256[2][2], uint256[2], bytes32, bytes32));

        return (pA, pB, pC, root, nullifierHash);
    }

    function _getCommitment(uint256 _amount) internal returns (uint256 commitmentWithoutAmount, uint256 commitment, bytes32 nullifier, bytes32 secret) {
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "forge-ffi-scripts/generateCommitment.js";
        inputs[2] = vm.toString(_amount);
        inputs[3] = vm.toString(address(this));
        bytes memory result = vm.ffi(inputs);
        (commitmentWithoutAmount, commitment, nullifier, secret) = abi.decode(result, (uint256, uint256, bytes32, bytes32));

        return (commitmentWithoutAmount, commitment, nullifier, secret);
    }

    function test_mixer_single_deposit() public {
        uint256 amountToDeposit = 2 ether;
        // 1. Generate commitment and deposit
        (uint256 commitmentWithoutAmount, uint256 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment(amountToDeposit);

        mixer.deposit{value: amountToDeposit}(commitmentWithoutAmount);

        uint256 testCommitment = mixer.TEST_COMMITMENT();
        assertEq(testCommitment, commitment);
        
        uint256 amountToWithdraw = 1 ether;
        uint256 newAmountToDeposit = amountToDeposit - amountToWithdraw;

        // 1.5 Generate new commitment
        (, uint256 newCommitment, bytes32 newNullifier, bytes32 newSecret) = _getCommitment(newAmountToDeposit);

        // 2. Generate witness and proof.
        uint256[] memory leaves = new uint256[](1);
        leaves[0] = commitment;
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash) =
            _getWitnessAndProof(nullifier, secret, amountToDeposit, recipient, relayer, newNullifier, newSecret, amountToWithdraw, leaves);

        // 3. Verify proof against the verifier contract.
        assertTrue(
            verifier.verifyProof(
                pA,
                pB,
                pC,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    amountToWithdraw,
                    newCommitment,
                    uint256(uint160(recipient)),
                    uint256(uint160(relayer)),
                    fee,
                    refund
                ]
            ),
            "Proof verification failed"
        );

        // 4. Withdraw funds from the contract.
        /*
        assertEq(recipient.balance, 0);
        assertEq(address(mixer).balance, 2 ether);
        mixer.withdraw(pA, pB, pC, root, nullifierHash, recipient, relayer, fee, refund, amountToWithdraw, amountToDeposit);
        assertEq(recipient.balance, 1 ether);
        assertEq(address(mixer).balance, 1 ether);
        */
    }

    /*
    function test_mixer_many_deposits() public {
        uint256 amountToDeposit = 2 ether;
        uint256[] memory leaves = new uint256[](200);

        // 1. Make 100 deposits with random commitments -- this will let us test with a non-empty merkle tree
        for (uint256 i = 0; i < 100; i++) {
            uint256 leaf = uint256(keccak256(abi.encode(i))) % FIELD_SIZE;

            mixer.deposit{value: 1 ether}(leaf);
            leaves[i] = leaf;
        }

        // 2. Generate commitment and deposit.
        (uint256 commitment, bytes32 nullifier, bytes32 secret) = _getCommitment(amountToDeposit);

        mixer.deposit{value: amountToDeposit}(commitment);
        leaves[100] = commitment;

        // 3. Make more deposits.
        for (uint256 i = 101; i < 200; i++) {
            uint256 leaf = uint256(keccak256(abi.encode(i))) % FIELD_SIZE;

            mixer.deposit{value: 1 ether}(leaf);
            leaves[i] = leaf;
        }

        // 4. Generate witness and proof.
        uint256 amountToWithdraw = 2 ether;
        (uint256 newCommitment, bytes32 newNullifier, bytes32 newSecret) = _getCommitment(amountToWithdraw);

        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash) =
            _getWitnessAndProof(nullifier, secret, recipient, relayer, newNullifier, newSecret, amountToWithdraw, newCommitment, leaves);

        // 5. Verify proof against the verifier contract.
        assertTrue(
            verifier.verifyProof(
                pA,
                pB,
                pC,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(uint160(recipient)),
                    uint256(uint160(relayer)),
                    fee,
                    refund,
                    amountToWithdraw,
                    newCommitment
                ]
            )
        );

        // 6. Withdraw funds from the contract.
        assertEq(recipient.balance, 0);
        assertEq(address(mixer).balance, 201 ether);
        mixer.withdraw(pA, pB, pC, root, nullifierHash, recipient, relayer, fee, refund, amountToWithdraw, newCommitment);
        assertEq(recipient.balance, 2 ether);
        assertEq(address(mixer).balance, 199 ether);
    }
    */
}
