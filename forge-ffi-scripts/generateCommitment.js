const { ethers } = require("ethers");
const { poseidonHash } = require("./utils/poseidon.js");
const { rbigint, bigintToHex } = require("./utils/bigint.js");

// Intended output: (bytes32 commitment, bytes32 nullifier, bytes32 secret)

////////////////////////////// MAIN ///////////////////////////////////////////

async function main() {
  const inputs = process.argv.slice(2, process.argv.length);

  const amount = inputs[0];
  const depositAddress = inputs[1];

  // 1. Generate random nullifier and secret
  const nullifier = rbigint(31);
  const secret = rbigint(31);

  // 2. Get commitment
  const commitmentWithoutAmount = await poseidonHash([nullifier, secret])
  const commitment = await poseidonHash([amount, depositAddress, commitmentWithoutAmount])

  // 3. Return abi encoded nullifier, secret, commitment
  const res = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "uint256", "bytes32", "bytes32"],
    [commitmentWithoutAmount, commitment, bigintToHex(nullifier), bigintToHex(secret)]
  );

  return res;
}

main()
  .then((res) => {
    process.stdout.write(res);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
