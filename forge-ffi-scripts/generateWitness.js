const path = require("path");
const snarkjs = require("snarkjs");
const { ethers } = require("ethers");

const {
  hexToBigint,
  bigintToHex,
} = require("./utils/bigint.js");

const { poseidonHash } = require("./utils/poseidon.js");
const { mimicMerkleTree } = require("./utils/mimcMerkleTree.js");

// Intended output: (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC, bytes32 root, bytes32 nullifierHash)

////////////////////////////// MAIN ///////////////////////////////////////////

async function main() {
  const inputs = process.argv.slice(2, process.argv.length);

  // 1. Get nullifier and secret and stuff
  const nullifier = hexToBigint(inputs[0]);
  const secret = hexToBigint(inputs[1]);
  const amountCommitted = BigInt(inputs[2]);
  const recipient = hexToBigint(inputs[3]);
  const relayer = hexToBigint(inputs[4]);
  const fee = BigInt(inputs[5]);
  const refund = BigInt(inputs[6]);
  const newNullifier = hexToBigint(inputs[7]);
  const newSecret = hexToBigint(inputs[8]);
  const amountToWithdraw = BigInt(inputs[9]);
  const depositAddress = hexToBigint(inputs[10]);

  // 2. Get nullifier hash
  const nullifierHash = await poseidonHash([nullifier]);

  // 3. Create merkle tree, insert leaves and get merkle proof for commitment
  const leaves = inputs.slice(11, inputs.length).map((l) => BigInt(l));

  console.log("leaves", leaves);

  const tree = await mimicMerkleTree(leaves);

  const commitmentWithoutAmount = await poseidonHash([nullifier, secret]);
  const commitment = await poseidonHash([amountCommitted, depositAddress, commitmentWithoutAmount]);
  console.log("commitment", commitment)

  const merkleProof = tree.proof(commitment);

  const newAmountToDeposit = amountCommitted - (amountToWithdraw + fee + refund);
  const newCommitmentWithoutAmount = await poseidonHash([newNullifier, newSecret]);
  const newCommitment = await poseidonHash([newAmountToDeposit, depositAddress, newCommitmentWithoutAmount]);

  console.log("root", merkleProof.pathRoot);

  // 4. Format witness input to exactly match circuit expectations
  const input = {
    // Public inputs
    root: merkleProof.pathRoot,
    nullifierHash: nullifierHash,
    recipient: recipient,
    relayer: relayer,
    fee: fee,
    refund: refund,
    amountToWithdraw: amountToWithdraw,
    newCommitment: newCommitment,

    // Private inputs
    committedAmount: amountCommitted,
    depositAddress: depositAddress,
    nullifier: nullifier,
    secret: secret,
    newNullifier: newNullifier,
    newSecret: newSecret,
    pathElements: merkleProof.pathElements.map((x) => x.toString()),
    pathIndices: merkleProof.pathIndices,
  };

  // 5. Create groth16 proof for witness
  const { proof } = await snarkjs.groth16.fullProve(
    input,
    path.join(__dirname, "../circuit_artifacts/withdraw_js/withdraw.wasm"),
    path.join(__dirname, "../circuit_artifacts/withdraw_final.zkey")
  );

  const pA = proof.pi_a.slice(0, 2);
  const pB = proof.pi_b.slice(0, 2);
  const pC = proof.pi_c.slice(0, 2);

  // 6. Return abi encoded witness
  const witness = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256[2]", "uint256[2][2]", "uint256[2]", "bytes32", "bytes32"],
    [
      pA,
      // Swap x coordinates: this is for proof verification with the Solidity precompile for EC Pairings, and not required
      // for verification with e.g. snarkJS.
      [
        [pB[0][1], pB[0][0]],
        [pB[1][1], pB[1][0]],
      ],
      pC,
      bigintToHex(merkleProof.pathRoot),
      bigintToHex(nullifierHash),
    ]
  );

  return witness;
}

main()
  .then((wtns) => {
    process.stdout.write(wtns);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
