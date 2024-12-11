const {
    poseidon,
} = require('vmtree-sdk');

// Computes the Poseidon hash of the given data, returning the result as a BigInt.
const poseidonHash = async (data) => {
  const poseidonOutput = poseidon(data);
  
  return poseidonOutput;
};

module.exports = {
  poseidonHash
};
