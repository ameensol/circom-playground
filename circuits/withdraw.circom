pragma circom 2.2.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "./merkleTree.circom";

// Commitment: Poseidon(amount, depositAddress, Poseidon(nullifier + secret))
// Future Commitment: Poseidon(amount, depositAddress, OG_commitment, Poseidon(nullifier, secret))
// 1st deposit -> null 

// computes Poseidon(nullifier + secret)
template CommitmentWithoutAmountHasher() {
    signal input nullifier;
    signal input secret;
    signal output commitment;
    signal output nullifierHash;

    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== nullifier;
    commitmentHasher.inputs[1] <== secret;

    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;

    commitment <== commitmentHasher.out;
    nullifierHash <== nullifierHasher.out;
}

template CommitmentHasher() {
    signal input amount;
    signal input depositAddress;
    signal input commitmentWithoutAmount;
    signal output commitment;

    component commitmentHasher = Poseidon(3);
    commitmentHasher.inputs[0] <== amount;
    commitmentHasher.inputs[1] <== depositAddress;
    commitmentHasher.inputs[2] <== commitmentWithoutAmount;
    commitment <== commitmentHasher.out;
}
// Verifies that commitment that corresponds to given secret and nullifier is included in the merkle tree of deposits
template Withdraw(levels) {
    // Public inputs
    signal input root;
    signal input nullifierHash;
    signal input amountToWithdraw;
    signal input newCommitment;
    signal input recipient; // not taking part in any computations
    signal input relayer;  // not taking part in any computations
    signal input fee;      // not taking part in any computations
    signal input refund;   // not taking part in any computations
    
    signal input committedAmount;
    signal input depositAddress;
    signal input nullifier;
    signal input secret;
    signal input newNullifier;
    signal input newSecret;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    component hasherWithoutAmount = CommitmentWithoutAmountHasher();
    hasherWithoutAmount.nullifier <== nullifier;
    hasherWithoutAmount.secret <== secret;
    hasherWithoutAmount.nullifierHash === nullifierHash;

    // verify existing commitment
    component hasher = CommitmentHasher();
    hasher.amount <== committedAmount;
    hasher.depositAddress <== depositAddress;
    hasher.commitmentWithoutAmount <== hasherWithoutAmount.commitment;

    component tree = MerkleTreeChecker(levels);
    tree.leaf <== hasher.commitment;
    tree.root <== root;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }

    // save new commitment 
    component newHasherWithoutAmount = CommitmentWithoutAmountHasher();
    newHasherWithoutAmount.nullifier <== newNullifier;
    newHasherWithoutAmount.secret <== newSecret;

    // verify that withdrawal amount is less than committed amount (overflow protection)
    component withdrawalAmountChecker = LessThan(248); // TODO check that all deposits are less than 2^248 at smart contract level - lol
    withdrawalAmountChecker.in[0] <== amountToWithdraw;
    withdrawalAmountChecker.in[1] <== committedAmount;
    withdrawalAmountChecker.out === 1; // true that withdrawal amount is less than committed amount

    // verify that fee amount is less than committed amount (overflow protection)
    component feeAmountChecker = LessThan(248); // TODO check that all deposits are less than 2^248 at smart contract level - lol
    feeAmountChecker.in[0] <== fee;
    feeAmountChecker.in[1] <== committedAmount;
    feeAmountChecker.out === 1; // true that fee amount is less than committed amount

    // verify that refund amount is less than committed amount (overflow protection)
    component refundAmountChecker = LessThan(248); // TODO check that all deposits are less than 2^248 at smart contract level - lol
    refundAmountChecker.in[0] <== refund;
    refundAmountChecker.in[1] <== committedAmount;
    refundAmountChecker.out === 1; // true that refund amount is less than committed amount

    // verify that new amount is less than committed amount (overflow protection)
    signal newAmount <== committedAmount - (amountToWithdraw + fee + refund);
    component amountChecker = LessThan(248); // TODO check that all deposits are less than 2^248 at smart contract level - lol
    amountChecker.in[0] <== newAmount;
    amountChecker.in[1] <== committedAmount;
    amountChecker.out === 1; // true that newAmount is less than committedAmount

    component newHasher = CommitmentHasher();
    newHasher.amount <== amountToWithdraw;
    newHasher.depositAddress <== depositAddress;
    newHasher.commitmentWithoutAmount <== newHasherWithoutAmount.commitment;
    newCommitment === newHasher.commitment;

    // Add hidden signals to make sure that tampering with recipient or fee will invalidate the snark proof
    // Most likely it is not required, but it's better to stay on the safe side and it only takes 2 constraints
    // Squares are used to prevent optimizer from removing those constraints
    signal recipientSquare;
    signal feeSquare;
    signal relayerSquare;
    signal refundSquare;
    recipientSquare <== recipient * recipient;
    feeSquare <== fee * fee;
    relayerSquare <== relayer * relayer;
    refundSquare <== refund * refund;
}

component main {public [root, nullifierHash, amountToWithdraw, newCommitment, recipient, relayer, fee, refund]} = Withdraw(20);
