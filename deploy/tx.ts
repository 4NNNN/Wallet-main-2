const ethers = require("ethers");

// Assuming you have the guardianHash value as a string, convert it to bytes32
const guardianHashValue = "0x0000000000000000000000000000000000000000000000000000000000000000"; // Replace this with the actual value
console.log(guardianHashValue)
// Encode the parameters into bytes
const encodedData = ethers.utils.defaultAbiCoder.encode(
  ["address[]", "uint256", "bytes32"],
  [["0x0D43eB5B8a47bA8900d84AA36656c92024e9772e"], 1, guardianHashValue]
);

console.log(encodedData)