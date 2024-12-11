const circomlibjs = require("circomlibjs");

// Poseidon(amount, depositAddress, Poseidon(nullifier, secret))
// Only computed on deposit with the three inputs above
process.stdout.write(circomlibjs.poseidon.createCode(3));
